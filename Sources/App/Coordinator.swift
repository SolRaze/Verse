import Foundation
import SwiftUI

/// Picks the engine and drives a play. The split (README): AVPlayer for anything that can
/// AirPlay to the car screen (YouTube video + mp4/mov/HLS), VLC for everything else.
/// Lyrics + CarPlay now-playing ride the VLC/audio path; the AVPlayer path is the video path.
///
/// Music-shaped YouTube plays (playlist entries, Spotify/SoundCloud matches) extract the
/// audio-only stream and go through VLC so they get lyrics, CarPlay, and the Live Activity —
/// same treatment as a local file. `item.isVideo` is the routing switch.
@MainActor
final class Coordinator: ObservableObject {
    enum Engine { case vlc, airplay }

    enum RepeatMode { case off, all, one }

    @Published var engine: Engine = .vlc
    @Published var showPlayer = false
    @Published var busy = false
    @Published var lastError: String?
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var queueIndex = 0
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off

    /// Restored when shuffle turns off.
    private var originalQueue: [LibraryItem] = []

    /// Player burger "View Track" / "View Artist": lands in the Library stack. RootView flips
    /// the tab, LibraryView pushes the destination and clears this.
    enum DeepLink: Equatable { case folder([String]), artist(String) }
    @Published var deepLink: DeepLink?

    func open(_ link: DeepLink) {
        showPlayer = false
        deepLink = link
    }

    /// What the mini bar and video pane show — kept here because the AVPlayer path has no
    /// published metadata of its own.
    @Published private(set) var nowTitle = ""
    @Published private(set) var nowArtist = ""

    let player = Player()
    let airPlayer = AirPlayVideoPlayer()

    // Strong, not unowned: `start` runs inside a detached Task, so a play can outlive whoever
    // created the store, and LibraryStore holds no reference back — there's no cycle to break.
    private let library: LibraryStore

    var upNext: [LibraryItem] {
        queue.indices.contains(queueIndex + 1) ? Array(queue[(queueIndex + 1)...]) : []
    }

    /// Id of the item now playing, for the now-playing indicator on library rows.
    var nowPlayingItemID: UUID? {
        queue.indices.contains(queueIndex) ? queue[queueIndex].id : nil
    }

    /// The item now playing, for the player's burger menu (like / share / info).
    var nowPlayingItem: LibraryItem? {
        queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
    }

    /// "Add to Queue > Play Next": right after the current track. Nothing playing = just play it.
    func playNext(_ item: LibraryItem) {
        guard !queue.isEmpty else { return play(item, in: [item]) }
        queue.insert(item, at: min(queueIndex + 1, queue.count))
    }

    /// "Add to Queue > Play Last": end of the queue. Nothing playing = just play it.
    func playLast(_ item: LibraryItem) {
        guard !queue.isEmpty else { return play(item, in: [item]) }
        queue.append(item)
    }

    init(library: LibraryStore) {
        self.library = library
        try? player.activateAudioSession()
        PlaybackBridge.shared.controls = player
        player.onNext = { [weak self] in self?.advance(auto: false) }
        player.onPrevious = { [weak self] in self?.step(-1) }
        player.onFinished = { [weak self] in self?.advance(auto: true) }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        let current = queue.indices.contains(queueIndex) ? queue[queueIndex] : nil
        if isShuffled {
            originalQueue = queue
            var rest = queue
            if let c = current { rest.removeAll { $0.id == c.id } }
            rest.shuffle()
            queue = (current.map { [$0] } ?? []) + rest
            queueIndex = 0
        } else {
            if !originalQueue.isEmpty { queue = originalQueue }
            queueIndex = current.flatMap { c in queue.firstIndex { $0.id == c.id } } ?? queueIndex
        }
    }

    func cycleRepeat() {
        repeatMode = switch repeatMode { case .off: .all; case .all: .one; case .one: .off }
    }

    /// Advance the queue. `auto` = the track ended on its own (honors repeat-one); manual next
    /// always moves forward. Both wrap when repeat-all is on.
    private func advance(auto: Bool) {
        if auto, repeatMode == .one {
            Task { await start(queue[queueIndex]) }   // replay the same track
            return
        }
        let next = queueIndex + 1
        if queue.indices.contains(next) {
            queueIndex = next
            Task { await start(queue[next]) }
        } else if repeatMode == .all, !queue.isEmpty {
            queueIndex = 0
            Task { await start(queue[0]) }
        }
    }

    func play(_ item: LibraryItem, in allItems: [LibraryItem]) {
        queue = allItems
        queueIndex = allItems.firstIndex(of: item) ?? 0
        Task { await start(item) }
    }

    /// Play a remote playlist from `index`. Every entry becomes a queue item: downloaded ones
    /// play the local file, YouTube ones stream, Spotify/SoundCloud ones get found via one
    /// YouTube search at play time (the `verse-search:` URL below).
    func play(_ playlist: RemotePlaylist, at index: Int) {
        let video = playlist.kind == .youtubeChannel
        queue = playlist.entries.map { entry in
            if let local = PlaylistMatcher.match(entry, in: library.items) { return local }
            let url = entry.watchURL
                ?? URL(string: "verse-search:?q=\(q(entry.artist + " " + entry.title))")!
            return LibraryItem(title: entry.title, artist: entry.artist,
                               source: .youtube(watchURL: url), isVideo: video)
        }
        queueIndex = min(index, queue.count - 1)
        Task { await start(queue[queueIndex]) }
    }

    func skip(_ delta: Int) { step(delta) }

    private func q(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func step(_ delta: Int) {
        let next = queueIndex + delta
        guard queue.indices.contains(next) else { return }
        queueIndex = next
        Task { await start(queue[next]) }
    }

    func jumpTo(_ item: LibraryItem) {
        guard let i = queue.firstIndex(of: item) else { return }
        queueIndex = i
        Task { await start(item) }
    }

    private func start(_ item: LibraryItem) async {
        busy = true
        lastError = nil
        nowTitle = item.title
        nowArtist = item.artist
        library.recordPlay(item)
        defer { busy = false }

        do {
            switch item.source {
            case .youtube(var watchURL):
                if watchURL.scheme == "verse-search" {
                    let terms = URLComponents(url: watchURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "q" })?.value ?? item.title
                    watchURL = try await PlaylistFetcher.youtubeSearch(terms)
                }
                if item.isVideo {
                    let ex = try await YouTubeSource.extract(watchURL: watchURL, audioOnly: false)
                    upgradePlaceholderTitle(item, from: ex)
                    engine = .airplay
                    player.stop()
                    airPlayer.skipSegments = ex.skipSegments
                    airPlayer.load(url: ex.streamURL)
                } else {
                    // Music: audio-only stream through VLC = lyrics + CarPlay + Live Activity.
                    let ex = try await YouTubeSource.extract(watchURL: watchURL, audioOnly: true)
                    engine = .vlc
                    airPlayer.stop()
                    player.load(
                        Player.Item(url: ex.streamURL, title: item.title, artist: item.artist,
                                    skipSegments: ex.skipSegments),
                        lyrics: nil)
                    resolveExtras(for: item, mediaURL: nil, playbackURL: ex.streamURL,
                                  title: cleanedTitle(item.title))
                }

            case .file:
                guard let url = library.resolveURL(item) else {
                    throw CocoaError(.fileNoSuchFile)
                }
                if item.isVideo, AirPlayVideoPlayer.canAirPlay(url) {
                    engine = .airplay
                    player.stop()
                    _ = url.startAccessingSecurityScopedResource()  // released on next load/stop
                    airPlayer.skipSegments = []
                    airPlayer.load(url: url)
                } else {
                    engine = .vlc
                    airPlayer.stop()
                    player.load(
                        Player.Item(url: url, title: item.title, artist: item.artist,
                                    artwork: Artwork.image(for: item.id.uuidString), scoped: true),
                        lyrics: nil)
                    resolveExtras(for: item, mediaURL: url, playbackURL: url, title: item.title)
                }
            }
            showPlayer = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Issue #4: sound first, network after. Lyrics + artwork resolve in the background and
    /// attach if the same track is still playing. The player holds the security scope for
    /// `mediaURL` while this runs, so the AVAsset reads inside are covered.
    private func resolveExtras(for item: LibraryItem, mediaURL: URL?, playbackURL: URL,
                               title: String) {
        Task {
            let lyrics = await LyricsResolver.resolve(
                mediaURL: mediaURL, title: title, artist: item.artist,
                duration: nil, cacheKey: item.id.uuidString)
            var art: UIImage?
            if let mediaURL {
                await Artwork.store(from: mediaURL, key: item.id.uuidString)  // lockscreen/CarPlay cover
                art = Artwork.image(for: item.id.uuidString)
            }
            player.attach(lyrics: lyrics, artwork: art, forURL: playbackURL)
        }
    }

    /// First successful extraction upgrades a pasted-URL placeholder title.
    private func upgradePlaceholderTitle(_ item: LibraryItem, from ex: YouTubeSource.Extracted) {
        guard case let .youtube(watchURL) = item.source,
              item.title == watchURL.absoluteString else { return }
        var named = item
        named.title = ex.title
        named.artist = ex.author
        library.update(named)
        nowTitle = ex.title
        nowArtist = ex.author
    }

    /// "Song (Official Video) [4K]" ruins exact LRCLIB lookups; the fuzzy fallback still gets
    /// a shot at the noise that survives this.
    private func cleanedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#,
                                   with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
