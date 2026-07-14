import AVFoundation
import Combine
import MobileVLCKit
import UIKit

/// One engine for everything: local files of any container/codec, and extracted YouTube streams.
///
/// VLC rather than AVPlayer because AVFoundation won't decode opus, ogg, wma, ape, mkv, or avi,
/// and a two-engine split means two now-playing integrations and two sets of bugs.
@MainActor
final class Player: NSObject, ObservableObject {
    struct Item {
        var url: URL
        var title: String
        var artist: String
        var album: String? = nil
        var artwork: UIImage? = nil
        /// SponsorBlock segments, seconds. Playback jumps to `end` on entering one.
        var skipSegments: [(start: TimeInterval, end: TimeInterval)] = []
        /// Set when the URL is a security-scoped bookmark resolution and must be released.
        var scoped: Bool = false
    }

    @Published private(set) var current: Item?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lyrics: Lyrics?

    /// Attach to a SwiftUI UIViewRepresentable to show video. Phone screen only — there is no
    /// route to the CarPlay display and attempting one is wasted effort. See README.
    let videoView = UIView()

    private let vlc = VLCMediaPlayer()
    private lazy var nowPlaying = NowPlaying(commands: .init(
        play: { [weak self] in self?.play() },
        pause: { [weak self] in self?.pause() },
        next: { [weak self] in self?.onNext?() },
        previous: { [weak self] in self?.onPrevious?() },
        seek: { [weak self] t in self?.seek(to: t) }))

    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    override init() {
        super.init()
        vlc.delegate = self
        vlc.drawable = videoView
    }

    /// Must succeed before any playback, or there is no background audio and no CarPlay.
    func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    func load(_ item: Item, lyrics: Lyrics?) {
        stop()
        current = item
        self.lyrics = lyrics

        if item.scoped { _ = item.url.startAccessingSecurityScopedResource() }
        vlc.media = VLCMedia(url: item.url)

        nowPlaying.begin(
            track: .init(title: item.title, artist: item.artist, album: item.album,
                         duration: 0, artwork: item.artwork),
            lyrics: lyrics)
        play()
        snapshot()
    }

    /// Widget state. Written on track change and play/pause flips only — never per tick,
    /// widget reloads are budgeted.
    private func snapshot() {
        PlaybackSnapshot.write(
            current.map { PlaybackSnapshot(title: $0.title, artist: $0.artist,
                                           isPlaying: isPlaying, hasArtwork: $0.artwork != nil) }
                ?? PlaybackSnapshot(title: "Nothing playing", artist: "", isPlaying: false, hasArtwork: false),
            artwork: current?.artwork)
    }

    func play() { vlc.play() }
    func pause() { vlc.pause() }

    func stop() {
        vlc.stop()
        if let item = current, item.scoped { item.url.stopAccessingSecurityScopedResource() }
        current = nil
        nowPlaying.end()
    }

    func seek(to time: TimeInterval) {
        vlc.time = VLCTime(int: Int32(time * 1000))
        syncNowPlaying()
    }

    private func syncNowPlaying() {
        nowPlaying.update(position: position, playing: isPlaying)
    }
}

extension Player: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerTimeChanged(_ notification: Notification!) {
        Task { @MainActor in
            position = Double(vlc.time.intValue) / 1000
            duration = Double(vlc.media?.length.intValue ?? 0) / 1000

            // SponsorBlock: entering a segment jumps to its end. That is the whole ad-skip feature.
            if let seg = current?.skipSegments.first(where: { position >= $0.start && position < $0.end - 0.5 }) {
                seek(to: seg.end)
                return
            }
            syncNowPlaying()
        }
    }

    nonisolated func mediaPlayerStateChanged(_ notification: Notification!) {
        Task { @MainActor in
            let was = isPlaying
            isPlaying = vlc.isPlaying
            syncNowPlaying()
            if was != isPlaying { snapshot() }
            if vlc.state == .ended { onNext?() }
        }
    }
}

extension Player: PlaybackControlling {
    func toggle() { isPlaying ? pause() : play() }
    func nextTrack() { onNext?() }
    func previousTrack() { onPrevious?() }
}
