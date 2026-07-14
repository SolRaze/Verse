import Foundation
import SwiftUI

/// Picks the engine and drives a play. The split (README): AVPlayer for anything that can
/// AirPlay to the car screen (YouTube + mp4/mov/HLS video), VLC for everything else.
/// Lyrics + CarPlay now-playing ride the VLC/audio path; the AVPlayer path is the video path.
@MainActor
final class Coordinator: ObservableObject {
    enum Engine { case vlc, airplay }

    @Published var engine: Engine = .vlc
    @Published var showPlayer = false
    @Published var busy = false
    @Published var lastError: String?

    let player = Player()
    let airPlayer = AirPlayVideoPlayer()

    private var queue: [LibraryItem] = []
    private var queueIndex = 0
    private unowned let library: LibraryStore

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

    private func step(_ delta: Int) {
        let next = queueIndex + delta
        guard queue.indices.contains(next) else { return }
        queueIndex = next
        Task { await start(queue[next]) }
    }

    private func start(_ item: LibraryItem) async {
        busy = true
        lastError = nil
        defer { busy = false }

        do {
            switch item.source {
            case .youtube(let watchURL):
                let ex = try await YouTubeSource.extract(watchURL: watchURL, audioOnly: false)
                // First successful extraction upgrades the placeholder title.
                if item.title == watchURL.absoluteString {
                    var named = item
                    named.title = ex.title
                    named.artist = ex.author
                    library.update(named)
                }
                engine = .airplay
                player.stop()
                airPlayer.skipSegments = ex.skipSegments
                airPlayer.load(url: ex.streamURL)

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
                    player.load(
                        Player.Item(url: url, title: item.title, artist: item.artist, scoped: true),
                        lyrics: lyrics)
                }
            }
            showPlayer = true
        } catch {
            lastError = error.localizedDescription
        }
    }
}
