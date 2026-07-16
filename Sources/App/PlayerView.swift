import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        switch coordinator.engine {
        case .airplay: VideoPane()
        case .vlc: NowPlayingPane(player: coordinator.player)
        }
    }
}

// MARK: - Audio: Spotify-shaped now playing

private struct NowPlayingPane: View {
    @ObservedObject var player: Player
    @EnvironmentObject var coordinator: Coordinator
    @State private var showLyrics = false

    private var hasLyrics: Bool {
        guard let l = player.lyrics else { return false }
        return l.isSynced || l.plain != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule().fill(.white.opacity(0.3)).frame(width: 36, height: 5).padding(.top, 8)

                // Album art near the top, then controls pulled up right under it.
                artworkWithLyrics.padding(.top, 16)
                titleRow.padding(.top, 20)
                lyricsButton
                scrubber
                transport

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }

    /// Album art, with synced lyrics laid over it (Apple-Music style) when toggled on. Tapping
    /// the art dismisses the lyric overlay.
    private var artworkWithLyrics: some View {
        ZStack {
            artOrVideo
            if showLyrics, let lyrics = player.lyrics, hasLyrics {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.72))
                LyricsPane(lyrics: lyrics, position: player.position) { player.seek(to: $0) }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .contentShape(Rectangle())
        .onTapGesture { if showLyrics { withAnimation(.snappy) { showLyrics = false } } }
    }

    @ViewBuilder private var artOrVideo: some View {
        if player.current?.artwork == nil, player.duration > 0 {
            // VLC-only video (mkv/webm/…) draws here; audio shows the placeholder square.
            VideoSurface(view: player.videoView)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let art = player.current?.artwork {
            // scaledToFit, not fill — fill zoom-crops non-square covers.
            Image(uiImage: art)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 20)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.4)))
        }
    }

    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "")
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            AirPlayButton().frame(width: 34, height: 34)
        }
        .padding(.top, 12)
    }

    /// Dedicated Lyrics toggle — the separate button that lays synced words over the artwork.
    @ViewBuilder private var lyricsButton: some View {
        if hasLyrics {
            Button { withAnimation(.snappy) { showLyrics.toggle() } } label: {
                Label(showLyrics ? "Hide Lyrics" : "Lyrics", systemImage: "quote.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(showLyrics ? .black : .white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(showLyrics ? .white : .white.opacity(0.15),
                                in: Capsule())
            }
            .padding(.top, 10)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { min(player.position, max(player.duration, 1)) },
                                  set: { player.seek(to: $0) }),
                   in: 0 ... max(player.duration, 1))
                .tint(.white)
            HStack {
                Text(timeString(player.position))
                Spacer()
                Text(timeString(player.duration))
            }
            .font(.caption2).foregroundStyle(.white.opacity(0.5)).monospacedDigit()
        }
        .padding(.top, 8)
    }

    private var transport: some View {
        HStack {
            Button { coordinator.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(coordinator.isShuffled ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.6)))
            }
            Spacer()
            Button { player.previousTrack() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
            }
            Spacer()
            Button { player.nextTrack() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
            Spacer()
            Button { coordinator.cycleRepeat() } label: {
                Image(systemName: coordinator.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(coordinator.repeatMode == .off ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.tint))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 18)
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context _: Context) -> UIView { view }
    func updateUIView(_: UIView, context _: Context) {}
}

/// Synced lyric sheet, Spotify-style: bold lines, active one lit, tap to seek, auto-scroll.
private struct LyricsPane: View {
    let lyrics: Lyrics
    let position: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        if lyrics.isSynced {
            let current = lyrics.lineIndex(at: position)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title2.bold())
                                .foregroundStyle(i == current ? .white : .white.opacity(0.35))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                                .onTapGesture { onSeek(line.time + lyrics.offset) }
                        }
                    }
                    .padding(.vertical, 80)
                }
                .onChange(of: current) { _, new in
                    guard let new else { return }
                    withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        } else if let plain = lyrics.plain {
            ScrollView {
                Text(plain)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 40)
            }
        }
    }
}

// MARK: - Video: YouTube-shaped watch screen

private struct VideoPane: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if coordinator.airPlayer.isExternal {
                    ContentUnavailableView("Playing on car display",
                                           systemImage: "car",
                                           description: Text("Video returns here when you disconnect."))
                } else {
                    AirPlayVideoView(player: coordinator.airPlayer.player)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.black)

            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coordinator.nowTitle).font(.headline).lineLimit(2)
                        Text(coordinator.nowArtist).font(.caption).foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)

                    HStack(spacing: 24) {
                        Button {
                            coordinator.airPlayer.isPlaying
                                ? coordinator.airPlayer.player.pause()
                                : coordinator.airPlayer.player.play()
                        } label: {
                            Image(systemName: coordinator.airPlayer.isPlaying ? "pause.fill" : "play.fill")
                        }
                        Button { coordinator.skip(-1) } label: { Image(systemName: "backward.fill") }
                        Button { coordinator.skip(1) } label: { Image(systemName: "forward.fill") }
                        Spacer()
                        AirPlayButton().frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                }

                if !coordinator.upNext.isEmpty {
                    Section("Up next") {
                        ForEach(coordinator.upNext) { item in
                            Button { coordinator.jumpTo(item) } label: {
                                QueueRow(item: item)
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(.dark)
    }
}

private struct QueueRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: item.thumbnailURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: item.isVideo ? "film" : "music.note")
                        .foregroundStyle(.secondary))
            }
            .frame(width: 84, height: 47)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline).lineLimit(2)
                if !item.artist.isEmpty {
                    Text(item.artist).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
