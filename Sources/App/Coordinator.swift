import AVFoundation
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
    @Published private(set) var queue: [LibraryItem] = [] { didSet { persistQueue() } }
    @Published private(set) var queueIndex = 0 { didSet { persistQueue() } }
    @Published private(set) var isShuffled = false
    @Published var repeatMode: RepeatMode = .off

    /// Restored when shuffle turns off.
    private var originalQueue: [LibraryItem] = []

    /// Player burger "View Track" / "View Artist": lands in the Library stack. RootView flips
    /// the tab, LibraryView pushes the destination and clears this.
    enum DeepLink: Equatable { case folder([String]), artist(String), album(String) }
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

    /// Queue-sheet editing. Offsets are into `upNext` (everything past the current track).
    func removeUpNext(at offsets: IndexSet) {
        for o in offsets.sorted(by: >) where queue.indices.contains(queueIndex + 1 + o) {
            queue.remove(at: queueIndex + 1 + o)
        }
    }

    func moveUpNext(from source: IndexSet, to destination: Int) {
        var next = upNext
        next.move(fromOffsets: source, toOffset: destination)
        queue = Array(queue.prefix(queueIndex + 1)) + next
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

    // MARK: - Queue persistence (survives force-quit; restored paused, nothing autoplays)

    private var queueFile: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("queue.json")
    }
    private struct SavedQueue: Codable { var items: [LibraryItem]; var index: Int }

    private func persistQueue() {
        try? JSONEncoder().encode(SavedQueue(items: queue, index: queueIndex))
            .write(to: queueFile, options: .atomic)
    }

    // MARK: - Sleep timer (Settings › Playback)

    @Published private(set) var sleepMinutes: Int?
    private var sleepTask: Task<Void, Never>?

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepMinutes = minutes
        guard let minutes else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled else { return }
            self?.player.pause()
            self?.airPlayer.player.pause()
            self?.sleepMinutes = nil
        }
    }

    /// AirPlay video holds a security scope on its file; released on the next play or stop
    /// (issue #7 — previously never released, one leaked handle per video).
    private var scopedVideoURL: URL?
    private func releaseVideoScope() {
        scopedVideoURL?.stopAccessingSecurityScopedResource()
        scopedVideoURL = nil
    }

    init(library: LibraryStore) {
        self.library = library
        try? player.activateAudioSession()
        if let data = try? Data(contentsOf: queueFile),
           let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
           !saved.items.isEmpty {
            queue = saved.items
            queueIndex = min(saved.index, saved.items.count - 1)
            primeRestored()
        }
        PlaybackBridge.shared.controls = player
        player.onNext = { [weak self] in self?.advance(auto: false) }
        player.onPrevious = { [weak self] in self?.step(-1) }
        player.onFinished = { [weak self] in self?.advance(auto: true) }
    }

    /// Launch restore: show the last-playing track in Now Playing (mini-player, lock screen) and
    /// load it paused at its saved position, so the app opens where it left off. Files only —
    /// re-loading a YouTube stream would need a network fetch on cold start. No play is counted.
    private func primeRestored() {
        guard queue.indices.contains(queueIndex) else { return }
        let item = queue[queueIndex]
        nowTitle = item.title
        nowArtist = item.artist
        guard case .file = item.source, let url = library.resolveURL(item) else { return }
        engine = .vlc
        player.load(Player.Item(url: url, title: item.title, artist: item.artist,
                                album: item.album,
                                artwork: Artwork.image(for: item.id.uuidString),
                                scoped: true, resumeKey: item.id.uuidString),
                    lyrics: nil, autoplay: false, resumeToSaved: true)
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

    /// `resume: true` continues from the track's saved position (the album/launch Resume actions);
    /// a normal tap leaves it false and starts from the beginning.
    func play(_ item: LibraryItem, in allItems: [LibraryItem], resume: Bool = false) {
        queue = allItems
        queueIndex = allItems.firstIndex(of: item) ?? 0
        Task { await start(item, resume: resume) }
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
        guard !queue.isEmpty else { return }   // empty playlist: queue[-1] would crash
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

    private func start(_ item: LibraryItem, resume: Bool = false) async {
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
                    releaseVideoScope()
                    scopedVideoURL = url.startAccessingSecurityScopedResource() ? url : nil
                    airPlayer.skipSegments = []
                    airPlayer.load(url: url)
                } else {
                    engine = .vlc
                    releaseVideoScope()
                    airPlayer.stop()
                    player.load(
                        Player.Item(url: url, title: item.title, artist: item.artist,
                                    artwork: Artwork.image(for: item.id.uuidString), scoped: true,
                                    resumeKey: item.id.uuidString),
                        lyrics: nil, resumeToSaved: resume)
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
            // Real duration → LRCLIB's exact /api/get match beats fuzzy search (plan phase 1).
            var duration: TimeInterval?
            if let mediaURL {
                duration = try? await AVURLAsset(url: mediaURL).load(.duration).seconds
                if duration?.isFinite != true { duration = nil }
            }
            let lyrics = await LyricsResolver.resolve(
                mediaURL: mediaURL, title: title, artist: item.artist,
                duration: duration, cacheKey: item.id.uuidString)
            var art: UIImage?
            if let mediaURL {
                await Artwork.store(from: mediaURL, key: item.id.uuidString)  // lockscreen/CarPlay cover
                art = Artwork.image(for: item.id.uuidString)
            }
            player.attach(lyrics: lyrics, artwork: art, forURL: playbackURL)
            // In-place metadata (inbox-3): whatever the chain found lives beside the file too.
            if lyrics != nil, case .file = item.source { library.exportLyricsSidecar(item) }
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
