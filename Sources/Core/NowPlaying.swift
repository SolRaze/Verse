import ActivityKit
import Foundation
import MediaPlayer
import UIKit

/// The entire CarPlay surface.
///
/// No CarPlay entitlement and no CPTemplateApplicationSceneDelegate are involved. Any app that
/// plays audio and populates MPNowPlayingInfoCenter appears on the car's Now Playing screen for
/// free; the steering-wheel and dashboard controls arrive through MPRemoteCommandCenter.
///
/// The interesting part is `render(...)`: the car draws the artwork large, so we draw the current
/// synced-lyric window into the artwork and republish it whenever the line changes. That puts
/// karaoke lyrics on the car display with no entitlement at all.
@MainActor
final class NowPlaying {
    struct Track {
        var title: String
        var artist: String
        var album: String?
        var duration: TimeInterval
        var artwork: UIImage?
    }

    /// Wire these to the player. Called from the car, the lock screen, and headphone buttons.
    struct Commands {
        var play: () -> Void
        var pause: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    /// Some head units cache artwork and won't refresh it per lyric line. Settings toggle; it
    /// pushes the current line into the artist field instead, which every unit updates reliably.
    var lyricsInTextFieldFallback: Bool {
        UserDefaults.standard.bool(forKey: Pref.carPlayTextFallback)
    }

    /// Master switch for rendering lyric lines into the published artwork. OFF by default (user
    /// request, inbox-2): lock screen and car show the real album art. Per-line lyrics still
    /// reach the Live Activity. Settings toggle restores karaoke artwork.
    var lyricsInArtwork: Bool {
        UserDefaults.standard.bool(forKey: Pref.lyricsInArtwork)
    }

    private let center = MPNowPlayingInfoCenter.default()
    private var track: Track?
    private var lyrics: Lyrics?
    private var shownLineIndex: Int??  // nil = never drawn; .some(nil) = drawn "before first line"

    init(commands: Commands) {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget { _ in commands.play(); return .success }
        rc.pauseCommand.addTarget { _ in commands.pause(); return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in
            (self?.isPlaying ?? false) ? commands.pause() : commands.play(); return .success
        }
        rc.nextTrackCommand.addTarget { _ in commands.next(); return .success }
        rc.previousTrackCommand.addTarget { _ in commands.previous(); return .success }
        rc.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            commands.seek(e.positionTime)
            return .success
        }
    }

    private var isPlaying: Bool {
        (center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) > 0
    }

    func begin(track: Track, lyrics: Lyrics?) {
        self.track = track
        self.lyrics = lyrics
        self.shownLineIndex = nil
        publish(position: 0, playing: false, image: track.artwork, lyricLine: nil)
        startActivity()
    }

    /// Late attach after begin() (issue #4): publish artwork once, adopt lyrics and start the
    /// Live Activity that begin() skipped because they hadn't resolved yet.
    func attach(lyrics: Lyrics?, artwork: UIImage?) {
        guard track != nil else { return }
        if let artwork {
            track?.artwork = artwork
            let pos = center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime]
                as? TimeInterval ?? 0
            publish(position: pos, playing: isPlaying, image: artwork, lyricLine: nil)
        }
        if let lyrics {
            self.lyrics = lyrics
            shownLineIndex = nil
            if activity == nil { startActivity() }
        }
    }

    func end() {
        track = nil
        lyrics = nil
        center.nowPlayingInfo = nil
        endActivity()
    }

    /// Call on every player tick and on every play/pause/seek.
    ///
    /// Cheap when nothing changed: the artwork is only re-rendered when the active lyric line
    /// actually changes, which is seconds apart. Never drive this off a display link.
    func update(position: TimeInterval, playing: Bool) {
        guard let track else { return }

        guard let lyrics, lyrics.isSynced else {
            publish(position: position, playing: playing, image: track.artwork, lyricLine: nil)
            return
        }

        let index = lyrics.lineIndex(at: position)
        syncActivity(index: index, playing: playing)
        guard lyricsInArtwork else {
            // Real album art was published in begin(); image nil keeps it and updates timing only.
            publish(position: position, playing: playing, image: nil, lyricLine: nil)
            return
        }
        if let shown = shownLineIndex, shown == index {
            publish(position: position, playing: playing, image: nil, lyricLine: nil)  // timing only
            return
        }
        shownLineIndex = .some(index)

        let line = index.map { lyrics.lines[$0].text }
        let image = lyricsInTextFieldFallback ? track.artwork : render(lyrics: lyrics, current: index)
        publish(position: position, playing: playing, image: image, lyricLine: line)
    }

    /// `image: nil` keeps whatever artwork is already published — reassigning MPMediaItemArtwork
    /// on every tick makes some head units flicker.
    private func publish(position: TimeInterval, playing: Bool, image: UIImage?, lyricLine: String?) {
        guard let track else { return }
        var info = center.nowPlayingInfo ?? [:]

        info[MPMediaItemPropertyTitle] = track.title
        info[MPMediaItemPropertyAlbumTitle] = track.album
        info[MPMediaItemPropertyPlaybackDuration] = track.duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0

        if lyricsInTextFieldFallback, let lyricLine {
            info[MPMediaItemPropertyArtist] = lyricLine
        } else {
            info[MPMediaItemPropertyArtist] = track.artist
        }

        if let image {
            info[MPMediaItemPropertyArtwork] = Self.artwork(image)
        }

        center.nowPlayingInfo = info
    }

    /// MediaPlayer calls the artwork block on ITS queue (e.g. jpegDataWithSize:), not main.
    /// Built inside a @MainActor method the closure inherits main-actor isolation and the Swift 6
    /// runtime dispatch-asserts — SIGTRAP. nonisolated here is load-bearing, not style.
    private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Live Activity (per-line lyrics on the Lock Screen, SPEC §6)

    private var activity: Activity<LyricActivityAttributes>?
    private var activityState: LyricActivityAttributes.ContentState?

    /// One activity per track, only when synced lyrics exist — a lyric-less track has nothing
    /// to show that the system now-playing surface doesn't already.
    private func startActivity() {
        endActivity()
        guard let track, let lyrics, lyrics.isSynced,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = LyricActivityAttributes.ContentState(
            previous: "", current: "", next: lyrics.lines.first?.text ?? "", isPlaying: false)
        activityState = state
        activity = try? Activity.request(
            attributes: LyricActivityAttributes(title: track.title, artist: track.artist),
            content: .init(state: state, staleDate: nil))
    }

    /// Cheap when nothing changed: dedups on ContentState equality, so it only hits ActivityKit
    /// on a line change or a play/pause flip — seconds apart, well inside update budgets.
    private func syncActivity(index: Int?, playing: Bool) {
        guard let activity, let lyrics else { return }
        let lines = lyrics.lines
        let state = LyricActivityAttributes.ContentState(
            previous: index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } ?? "",
            current: index.map { lines[$0].text } ?? "",
            next: index.map { $0 + 1 < lines.count ? lines[$0 + 1].text : "" }
                ?? lines.first?.text ?? "",
            isPlaying: playing)
        guard state != activityState else { return }
        activityState = state
        let sent = Sent(activity)
        Task { await sent.value.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        if let activity {
            let sent = Sent(activity)
            Task { await sent.value.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        activityState = nil
    }

    /// ActivityKit's Activity is thread-safe but not declared Sendable, so awaiting its async
    /// methods from this @MainActor class trips Swift 6 region checking. Box it.
    private struct Sent<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    // MARK: - Lyrics -> artwork

    /// Draws previous / current / next lines onto a square canvas, current line emphasized.
    /// Square because that is what every head unit expects an album cover to be.
    private func render(lyrics: Lyrics, current: Int?) -> UIImage {
        let side: CGFloat = 600
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))

        // A window of lines around the current one, so the driver has context without reading.
        let window: [(text: String, active: Bool)] = {
            guard let current else {
                return lyrics.lines.prefix(2).map { ($0.text, false) }
            }
            let lo = max(0, current - 1)
            let hi = min(lyrics.lines.count - 1, current + 2)
            return (lo...hi).map { (lyrics.lines[$0].text, $0 == current) }
        }()

        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

            let inset: CGFloat = 40
            let width = side - inset * 2
            var blocks: [(NSAttributedString, CGRect)] = []
            var totalHeight: CGFloat = 0

            for entry in window where !entry.text.isEmpty {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: entry.active ? 46 : 32,
                                             weight: entry.active ? .bold : .regular),
                    .foregroundColor: entry.active ? UIColor.white : UIColor(white: 1, alpha: 0.4),
                    .paragraphStyle: style,
                ]
                let string = NSAttributedString(string: entry.text, attributes: attrs)
                let bounds = string.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

                blocks.append((string, CGRect(x: inset, y: 0, width: width, height: ceil(bounds.height))))
                totalHeight += ceil(bounds.height) + 18
            }

            var y = max(inset, (side - totalHeight) / 2)
            for (string, rect) in blocks {
                string.draw(with: rect.offsetBy(dx: 0, dy: y),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                y += rect.height + 18
            }
        }
    }
}
