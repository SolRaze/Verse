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

    @Published var engine: Engine = .vlc
    @Published var showPlayer = false
    @Published var busy = false
    @Published var lastError: String?
    @Published private(set) var queue: [LibraryItem] = []
    @Published private(set) var queueIndex = 0

    /// What the mini bar and video pane show — kept here because the AVPlayer path has no
    /// published metadata of its own.
    @Published private(set) var nowTitle = ""
    @Published private(set) var nowArtist = ""

    let player = Player()
    let airPlayer = AirPlayVideoPlayer()

    private unowned let library: LibraryStore

    var upNext: [LibraryItem] {
        queue.indices.contains(queueIndex + 1) ? Array(queue[(queueIndex + 1)...]) : []
    }

    init(library: LibraryStore) {
        self.library = library
        try? player.activateAudioSession()
        PlaybackBridge.shared.controls = player
        player.onNext = { [weak self] in self?.step(1) }
        player.onPrevious = { [weak self] in self?.step(-1) }
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
                    let lyrics = await LyricsResolver.resolve(
                        mediaURL: nil, title: cleanedTitle(item.title), artist: item.artist,
                        duration: nil, cacheKey: item.id.uuidString)
                    player.load(
                        Player.Item(url: ex.streamURL, title: item.title, artist: item.artist,
                                    skipSegments: ex.skipSegments),
                        lyrics: lyrics)
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
                    let lyrics = await LyricsResolver.resolve(
                        mediaURL: url, title: item.title, artist: item.artist,
                        duration: nil, cacheKey: item.id.uuidString)
                    await Artwork.store(from: url, key: item.id.uuidString)  // lockscreen/CarPlay cover
                    player.load(
                        Player.Item(url: url, title: item.title, artist: item.artist,
                                    artwork: Artwork.image(for: item.id.uuidString), scoped: true),
                        lyrics: lyrics)
                }
            }
            showPlayer = true
        } catch {
            lastError = error.localizedDescription
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
