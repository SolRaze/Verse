import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        switch coordinator.engine {
        case .airplay: AirPlayPane(air: coordinator.airPlayer)
        case .vlc: VLCPane(player: coordinator.player)
        }
    }
}

/// Video path: AVPlayer surface + the AirPlay button that reaches the car screen.
private struct AirPlayPane: View {
    @ObservedObject var air: AirPlayVideoPlayer

    var body: some View {
        VStack {
            if air.isExternal {
                ContentUnavailableView("Playing on car display",
                                       systemImage: "car",
                                       description: Text("Video returns here when you disconnect."))
            } else {
                AirPlayVideoView(player: air.player)
            }
            AirPlayButton()
                .frame(width: 44, height: 44)
                .padding(.bottom)
        }
        .background(.black)
    }
}

/// Audio (and VLC-only video) path: transport, video surface when relevant, synced lyrics.
private struct VLCPane: View {
    @ObservedObject var player: Player

    var body: some View {
        VStack(spacing: 16) {
            if player.current != nil {
                VideoSurface(view: player.videoView)
                    .aspectRatio(16 / 9, contentMode: .fit)

                Text(player.current?.title ?? "").font(.headline).lineLimit(1)

                LyricsPane(lyrics: player.lyrics, position: player.position) { time in
                    player.seek(to: time)
                }

                // Scrubber + transport
                Slider(value: Binding(get: { player.position },
                                      set: { player.seek(to: $0) }),
                       in: 0 ... max(player.duration, 1))
                    .padding(.horizontal)

                HStack(spacing: 44) {
                    Button { player.onPrevious?() } label: { Image(systemName: "backward.fill") }
                    Button { player.isPlaying ? player.pause() : player.play() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.largeTitle)
                    }
                    Button { player.onNext?() } label: { Image(systemName: "forward.fill") }
                }
                .padding(.bottom)
            }
        }
        .padding(.top)
    }
}

private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context _: Context) -> UIView { view }
    func updateUIView(_: UIView, context _: Context) {}
}

/// Synced lyric column: auto-scrolls with playback, tap a line to seek there.
private struct LyricsPane: View {
    let lyrics: Lyrics?
    let position: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        Group {
            if let lyrics, lyrics.isSynced {
                let current = lyrics.lineIndex(at: position)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(i == current ? .title3.bold() : .body)
                                    .foregroundStyle(i == current ? .primary : .secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(i)
                                    .onTapGesture { onSeek(line.time + lyrics.offset) }
                            }
                        }
                        .padding(.vertical, 60)
                    }
                    .onChange(of: current) { _, new in
                        guard let new else { return }
                        withAnimation { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            } else if let plain = lyrics?.plain {
                ScrollView { Text(plain).padding() }
            } else {
                Spacer()
            }
        }
        .frame(maxHeight: .infinity)
    }
}
