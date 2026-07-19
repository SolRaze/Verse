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
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var infoItem: LibraryItem?
    @State private var showQueue = false

    private var hasLyrics: Bool {
        guard let l = player.lyrics else { return false }
        return l.isSynced || l.plain != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showLyrics, let lyrics = player.lyrics, hasLyrics {
                LyricsScreen(player: player, lyrics: lyrics, showQueue: $showQueue) {
                    withAnimation(.snappy) { showLyrics = false }
                }
            } else {
                VStack(spacing: 0) {
                    topBar

                    // Album art near the top, offset so it doesn't crowd the top bar.
                    artOrVideo
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 300)
                        .padding(.top, 32)
                    titleRow.padding(.top, 28)
                    scrubber.padding(.top, 8)
                    transport
                    bottomRow

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(item: $infoItem) { InfoSheet(item: $0) }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .preferredColorScheme(.dark)
    }

    /// SoundCloud-shaped top: just the minimize chevron, top right, in a dark circle.
    private var topBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.1), in: Circle())
            }
        }
        .padding(.top, 14)
    }

    private var burgerMenu: some View {
        Menu {
            if let item = coordinator.nowPlayingItem {
                Button { infoItem = item } label: { Label("Info", systemImage: "info.circle") }
                Button {
                    var it = item
                    it.liked.toggle()
                    library.update(it)
                } label: {
                    let liked = library.items.first { $0.id == item.id }?.liked ?? item.liked
                    Label(liked ? "Unlike" : "Like", systemImage: liked ? "heart.fill" : "heart")
                }
                if let url = shareURL(item) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                // Only library files live somewhere to view; remote queue entries don't.
                if case .file = item.source {
                    Button { coordinator.open(.folder(item.folders)) } label: {
                        Label("View Track", systemImage: "music.note")
                    }
                }
                if !item.artist.isEmpty {
                    Button { coordinator.open(.artist(item.artist)) } label: {
                        Label("View Artist", systemImage: "music.mic")
                    }
                }
            }
        } label: {
            // Bare dots in a dim circle, Apple-Music style.
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.1), in: Circle())
        }
    }

    private func shareURL(_ item: LibraryItem) -> URL? {
        switch item.source {
        case .youtube(let watchURL): watchURL.scheme?.hasPrefix("http") == true ? watchURL : nil
        case .file: library.resolveURL(item)
        }
    }

    @ViewBuilder private var artOrVideo: some View {
        // Square corners on the art, per the redesign — no rounding anywhere here.
        if player.current?.artwork == nil, player.duration > 0 {
            // VLC-only video (mkv/webm/…) draws here; audio shows the placeholder square.
            VideoSurface(view: player.videoView)
                .aspectRatio(16 / 9, contentMode: .fit)
        } else if let art = player.current?.artwork {
            // scaledToFit, not fill — fill zoom-crops non-square covers.
            Image(uiImage: art)
                .resizable().scaledToFit()
                .shadow(radius: 20)
        } else {
            Rectangle()
                .fill(.white.opacity(0.08))
                .overlay(Image(systemName: "music.note").font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.4)))
        }
    }

    /// Apple-Music-shaped: title/artist left, the burger in a circle on the right.
    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "")
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            burgerMenu
        }
        .padding(.top, 12)
    }

    /// Apple Music's bottom row: lyrics left, AirPlay center, queue right.
    private var bottomRow: some View {
        HStack {
            Button { withAnimation(.snappy) { showLyrics = true } } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(hasLyrics ? .white : .white.opacity(0.25))
            }
            .disabled(!hasLyrics)
            Spacer()
            AirPlayButton().frame(width: 34, height: 34)
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 6)
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
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32))
                    .frame(width: 68, height: 68)
                    .glassEffect(.regular.interactive())
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

/// Fullscreen lyrics, Files-app player shaped: close top right, a bare scrubber (no transport on
/// it), play bottom left, queue bottom right, with the track pill staying visible above the bar.
private struct LyricsScreen: View {
    @ObservedObject var player: Player
    let lyrics: Lyrics
    @Binding var showQueue: Bool
    let onClose: () -> Void
    @State private var samples: [Float]?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.interactive())
                }
            }
            .padding(.top, 14)

            LyricsPane(lyrics: lyrics, position: player.position) { player.seek(to: $0) }

            // The track pill that stays put while reading — the wave scrubber lives inside it.
            // Real audio drawn when AVFoundation can decode the file; Files-style ticks when it
            // can't (VLC-only codecs, remote streams — VLC exposes no decoded samples).
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.current?.title ?? "").font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(player.current?.artist ?? "").font(.caption2)
                            .foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                WaveScrubber(samples: samples,
                             position: player.position,
                             duration: player.duration) { player.seek(to: $0) }
                    .frame(height: 28)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            .task(id: player.current?.url) {
                samples = nil
                if let url = player.current?.url { samples = await Waveform.load(url: url) }
            }

            HStack {
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive())
                }
                Spacer()
                Button { showQueue = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive())
                }
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }
}

/// The wave scrubber: real waveform bars when samples exist, Files-style ticks otherwise, with
/// a playhead line. Drag to seek. Shared by the lyrics pill and (via Settings) the mini player.
struct WaveScrubber: View {
    let samples: [Float]?
    let position: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let frac = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let x = frac * w
            Canvas { ctx, _ in
                if let samples, !samples.isEmpty {
                    let step = w / CGFloat(samples.count)
                    for (i, v) in samples.enumerated() {
                        let dx = CGFloat(i) * step
                        let bh = max(3, CGFloat(v) * (h - 4))
                        ctx.fill(
                            Path(roundedRect: CGRect(x: dx, y: (h - bh) / 2,
                                                     width: max(step - 1.5, 1), height: bh),
                                 cornerRadius: 1),
                            with: .color(.white.opacity(dx < x ? 0.9 : 0.3)))
                    }
                } else {
                    for i in 0 ..< max(Int(w / 6), 2) {
                        let dx = CGFloat(i) * 6 + 1.5
                        ctx.fill(Path(ellipseIn: CGRect(x: dx, y: h / 2 - 1, width: 2, height: 2)),
                                 with: .color(.white.opacity(dx < x ? 0.9 : 0.35)))
                    }
                }
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: h))
                ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { g in
                        guard duration > 0 else { return }
                        onSeek(min(max(g.location.x / w, 0), 1) * duration)
                    })
        }
    }
}

/// Up-next list behind the lyrics screen's queue button.
private struct QueueSheet: View {
    @EnvironmentObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if coordinator.upNext.isEmpty {
                    ContentUnavailableView("Queue is empty", systemImage: "list.bullet")
                } else {
                    ForEach(coordinator.upNext) { item in
                        Button { coordinator.jumpTo(item) } label: { QueueRow(item: item) }
                            .tint(.primary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
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
