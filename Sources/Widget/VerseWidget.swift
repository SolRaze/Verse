import AppIntents
import SwiftUI
import WidgetKit

// Intents live in Sources/Core/Intents.swift, shared with the app target — they must run in the
// app process (AudioPlaybackIntent) but be visible here for the Buttons.

struct VerseEntry: TimelineEntry {
    let date: Date
    let snapshot: PlaybackSnapshot?
    let artwork: UIImage?
}

struct VerseProvider: TimelineProvider {
    func placeholder(in _: Context) -> VerseEntry {
        VerseEntry(date: .now, snapshot: nil, artwork: nil)
    }
    func getSnapshot(in _: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(entry())
    }
    /// Never-refresh policy: the app pushes updates via WidgetCenter on track change and on
    /// play/pause. A polling timeline would just burn the reload budget for nothing.
    func getTimeline(in _: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }
    private func entry() -> VerseEntry {
        VerseEntry(date: .now, snapshot: PlaybackSnapshot.read(), artwork: PlaybackSnapshot.readArtwork())
    }
}

struct VerseWidgetView: View {
    var entry: VerseEntry

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

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VerseNowPlaying", provider: VerseProvider()) {
            VerseWidgetView(entry: $0)
        }
        .configurationDisplayName("Now Playing")
        .description("Controls whatever Verse is playing.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Live Activity: per-line lyrics on the Lock Screen (SPEC §6)

struct LyricLiveActivity: Widget {
    /// A previous/next lyric row that reserves its line height even when empty (a space keeps the
    /// baseline), so filling it in doesn't shove the current line up or down.
    private static func side(_ text: String) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            .opacity(text.isEmpty ? 0 : 1)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            // Fixed three-slot layout: each row keeps its height whether or not it has text, so
            // the card never resizes and the current line doesn't hop as previous/next fill in.
            VStack(spacing: 4) {
                Self.side(context.state.previous)
                Text(context.state.current.isEmpty ? context.attributes.title : context.state.current)
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Self.side(context.state.next)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // iPhone 17e has no Dynamic Island; this is the minimum ActivityKit requires,
            // and it works if the activity ever runs on hardware that does.
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.current.isEmpty ? context.attributes.title : context.state.current)
                        .font(.headline).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "music.note" : "pause.fill")
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "music.note")
            }
        }
    }
}

@main
struct VerseWidgets: WidgetBundle {
    var body: some Widget {
        VerseWidget()
        LyricLiveActivity()
    }
}
