import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents
//
// AudioPlaybackIntent, not AppIntent. The difference is load-bearing: a plain widget intent runs
// inside the widget extension process, which has no background-audio entitlement and cannot
// activate an AVAudioSession — the tap would do nothing. Conforming to AudioPlaybackIntent makes
// the system launch the *app* in the background to perform it, with audio permitted.

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause"

    func perform() async throws -> some IntentResult {
        await PlaybackBridge.shared.toggle()
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Track"

    func perform() async throws -> some IntentResult {
        await PlaybackBridge.shared.next()
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Track"

    func perform() async throws -> some IntentResult {
        await PlaybackBridge.shared.previous()
        return .result()
    }
}

/// The intent runs in the app process, so it can reach the live Player directly.
/// Set `PlaybackBridge.shared.player` when the app builds its Player.
@MainActor
final class PlaybackBridge {
    static let shared = PlaybackBridge()
    weak var player: Player?

    func toggle() {
        guard let player else { return }
        player.isPlaying ? player.pause() : player.play()
    }
    func next() { player?.onNext?() }
    func previous() { player?.onPrevious?() }
}

// MARK: - Widget

struct RoadieEntry: TimelineEntry {
    let date: Date
    let snapshot: PlaybackSnapshot?
    let artwork: UIImage?
}

struct RoadieProvider: TimelineProvider {
    func placeholder(in _: Context) -> RoadieEntry {
        RoadieEntry(date: .now, snapshot: nil, artwork: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (RoadieEntry) -> Void) {
        completion(entry())
    }
    /// Never-refresh policy: the app pushes updates via WidgetCenter on track change and on
    /// play/pause. A polling timeline would just burn the reload budget for nothing.
    func getTimeline(in _: Context, completion: @escaping (Timeline<RoadieEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }
    private func entry() -> RoadieEntry {
        RoadieEntry(date: .now, snapshot: PlaybackSnapshot.read(), artwork: PlaybackSnapshot.readArtwork())
    }
}

struct RoadieWidgetView: View {
    var entry: RoadieEntry

    var body: some View {
        HStack(spacing: 12) {
            if let art = entry.artwork {
                Image(uiImage: art)
                    .resizable().scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot?.title ?? "Nothing playing")
                    .font(.headline).lineLimit(1)
                Text(entry.snapshot?.artist ?? "")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)

                HStack(spacing: 16) {
                    Button(intent: PreviousTrackIntent()) { Image(systemName: "backward.fill") }
                    Button(intent: TogglePlaybackIntent()) {
                        Image(systemName: (entry.snapshot?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    }
                    Button(intent: NextTrackIntent()) { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct RoadieWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoadieNowPlaying", provider: RoadieProvider()) {
            RoadieWidgetView(entry: $0)
        }
        .configurationDisplayName("Now Playing")
        .description("Controls whatever Roadie is playing.")
        .supportedFamilies([.systemMedium])
    }
}
