import SwiftUI
import MediaPlayer

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
    @State private var showLyrics = false
    @State private var infoItem: LibraryItem?
    @State private var showQueue = false

    private var hasLyrics: Bool {
        guard let l = player.lyrics else { return false }
        return l.isSynced || l.plain != nil
    }

    @AppStorage(Pref.tintedBackground) private var tintedBG = false
    @AppStorage(Pref.likeGlyph) private var likeGlyph = "heart"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Optional cover-tinted wash (Settings › Lyrics › Tinted Background). Solid dim
            // colour, not a gradient — the no-gradient rule holds.
            if tintedBG, let art = player.current?.artwork,
               let c = Artwork.dominantColor(art) {
                Color(c).opacity(0.18).ignoresSafeArea()
            }

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
                    volumeRow.padding(.top, 4)
                    bottomRow
                    shareRow.padding(.top, 10)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(item: $infoItem) { InfoSheet(item: $0) }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .preferredColorScheme(.dark)
    }

    /// Top: just the options (•••) menu, top right, glass. Minimize is gone — the sheet's own
    /// swipe-down dismiss covers it (#3).
    private var topBar: some View {
        HStack {
            Spacer()
            optionsMenu
        }
        .padding(.top, 14)
    }

    private var optionsMenu: some View {
        Menu {
            if let item = coordinator.nowPlayingItem {
                Button { infoItem = item } label: { Label("Info", systemImage: "info.circle") }
                // Only library files live somewhere to view; remote queue entries don't.
                if case .file = item.source {
                    // Album page, not the disk folder — file locations never display.
                    Button {
                        coordinator.open(item.albumKey.isEmpty ? .folder([]) : .album(item.albumKey))
                    } label: {
                        Label("View Album", systemImage: "square.stack")
                    }
                }
                if !item.artist.isEmpty {
                    Button { coordinator.open(.artist(item.artist)) } label: {
                        Label("View Artist", systemImage: "music.mic")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive())
        }
    }

    /// Tap = like/unlike the current track; hold = pick one of five glyphs the button wears
    /// (#3, `Pref.likeGlyph`). Sits where the options menu used to, right of the title.
    private var favouriteButton: some View {
        let item = coordinator.nowPlayingItem
        let liked = item.map { i in library.items.first { $0.id == i.id }?.liked ?? i.liked } ?? false
        return Menu {
            Picker("Icon", selection: $likeGlyph) {
                ForEach(Pref.likeGlyphs, id: \.self) { g in
                    Label(g.replacingOccurrences(of: ".", with: " ").capitalized, systemImage: g).tag(g)
                }
            }
        } label: {
            Image(systemName: liked ? "\(likeGlyph).fill" : likeGlyph)
                .font(.body.weight(.semibold))
                .foregroundStyle(liked ? AnyShapeStyle(.tint) : AnyShapeStyle(.white.opacity(0.8)))
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive())
        } primaryAction: {
            guard var it = item else { return }
            it.liked.toggle()
            library.update(it)
        }
        .disabled(item == nil)
    }

    /// System volume, below the transport (#1). MPVolumeView drives the real hardware volume;
    /// route button hidden (AirPlay already lives in the bottom row). Simulator shows it inert.
    private var volumeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.white.opacity(0.5))
            SystemVolumeSlider().frame(height: 28)
            Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
    }

    /// Share the current track's URL, below the bottom-row icons (#2). Pulled out of the options
    /// menu into its own glass button.
    @ViewBuilder private var shareRow: some View {
        if let item = coordinator.nowPlayingItem, let url = shareURL(item) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .glassEffect(.regular.interactive())
            }
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
        // Gate on the ITEM being video, not duration>0 — coverless audio was rendering the
        // empty VLC surface instead of the placeholder (issue #8).
        if player.current?.artwork == nil, coordinator.nowPlayingItem?.isVideo == true {
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

    /// Apple-Music-shaped: title/artist left, the favourite button on the right (#3).
    private var titleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.title ?? "")
                    .font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
            favouriteButton
        }
        .padding(.top, 12)
    }

    /// Apple Music's bottom row: lyrics, sleep timer, AirPlay, queue — glass circles to match the
    /// top controls (#6).
    private var bottomRow: some View {
        HStack {
            Button { withAnimation(.snappy) { showLyrics = true } } label: {
                Image(systemName: "quote.bubble.fill")
                    .font(.body)
                    .foregroundStyle(hasLyrics ? .white : .white.opacity(0.25))
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive())
            }
            .disabled(!hasLyrics)
            Spacer()
            sleepMenu
            Spacer()
            AirPlayButton()
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive())
            Spacer()
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.interactive())
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
    }

    /// Sleep timer (moved off Settings): a moon that fills while a timer is running; the menu shows
    /// the remaining minutes and lets you change or cancel it.
    private var sleepMenu: some View {
        Menu {
            if let m = coordinator.sleepMinutes {
                Text("~\(m) min left")
                Button("Cancel Timer") { coordinator.setSleepTimer(minutes: nil) }
                Divider()
            }
            ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                Button("\(m) min") { coordinator.setSleepTimer(minutes: m) }
            }
        } label: {
            Image(systemName: coordinator.sleepMinutes != nil ? "moon.fill" : "moon")
                .font(.body)
                .foregroundStyle(coordinator.sleepMinutes != nil ? .white : .white.opacity(0.6))
                .frame(width: 34, height: 34)
                .glassEffect(.regular.interactive())
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
    @AppStorage(Pref.lyricsCoverColour) private var coverColour = false

    /// The active-line tint: the cover's dominant colour when the setting is on and there's
    /// artwork, otherwise stock white.
    private var lineTint: Color {
        guard coverColour, let art = player.current?.artwork,
              let c = Artwork.dominantColor(art) else { return .white }
        return Color(c)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Files-style top bar: track name centered, close right. The clear square mirrors
            // the close button so the title actually centers.
            HStack {
                Color.clear.frame(width: 34, height: 34)
                Spacer()
                // .headline = the one title style used on inline bars app-wide (user request:
                // bigger, uniform).
                Text(player.current?.title ?? "")
                    .font(.headline).lineLimit(1)
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

            LyricsPane(lyrics: lyrics, position: player.position, tint: lineTint) { player.seek(to: $0) }

            // The wave alone in a capsule, no name (the top bar carries it) — same pill
            // language as the dock mini player, per reference/files-layer.png. Real audio when
            // AVFoundation can decode the file; Files-style ticks when it can't (VLC-only
            // codecs, remote streams — VLC exposes no decoded samples).
            WaveScrubber(samples: samples,
                         position: player.position,
                         duration: player.duration) { player.seek(to: $0) }
                .frame(height: 30)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.white.opacity(0.08), in: Capsule())
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

/// The queue sheet: player-black background (the grouped-grey default looked like another
/// app), Now Playing pinned on top, Up Next below with drag-reorder (Edit) and swipe-remove.
private struct QueueSheet: View {
    @EnvironmentObject var coordinator: Coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var infoItem: LibraryItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            if coordinator.nowPlayingItem != nil {
                // Same widget card as Home — above the List so it gets no row chrome
                // (separators, edit-mode insets), just its own rounded card.
                NowPlayingCard(player: coordinator.player)
                    .padding(14)
                    .background(Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            List {
                Section {
                    if coordinator.upNext.isEmpty {
                        Text("Nothing queued — hold a song and Add to Queue.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        // No onDelete: that's what drew the minus circles in edit mode. The
                        // handle only reorders; removal is swipe or the hold menu.
                        ForEach(coordinator.upNext) { item in
                            Button { coordinator.jumpTo(item) } label: { QueueRow(item: item) }
                                .tint(.primary)
                                .listRowBackground(Color.clear)
                                .swipeActions {
                                    Button(role: .destructive) { remove(item) } label: {
                                        Label("Remove", systemImage: "minus.circle")
                                    }
                                }
                                .contextMenu {
                                    Button { remove(item) } label: {
                                        Label("Remove from Queue", systemImage: "minus.circle")
                                    }
                                    ItemContextMenu(item: item, queue: coordinator.upNext,
                                                    infoItem: $infoItem)
                                }
                        }
                        .onMove { coordinator.moveUpNext(from: $0, to: $1) }
                    }
                } header: {
                    Text("Up Next").foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Always-on drag handles on the right — no Edit mode dance. Swipe deletes.
            .environment(\.editMode, .constant(.active))
            }
            .background(Color.black)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(Color.black)
        .themedTint()
        .preferredColorScheme(.dark)
        .modifier(TrackSheets(infoItem: $infoItem))
    }

    private func remove(_ item: LibraryItem) {
        if let i = coordinator.upNext.firstIndex(of: item) {
            coordinator.removeUpNext(at: IndexSet(integer: i))
        }
    }
}

private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context _: Context) -> UIView { view }
    func updateUIView(_: UIView, context _: Context) {}
}

/// System volume slider — MPVolumeView with its route button hidden, so it's just the slider
/// wired to real hardware volume. Inert in the simulator (no volume there).
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context _: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.showsRouteButton = false
        v.tintColor = .white
        return v
    }
    func updateUIView(_: MPVolumeView, context _: Context) {}
}

/// Synced lyric sheet, Spotify-style: bold lines, active one lit, tap to seek, auto-scroll.
private struct LyricsPane: View {
    let lyrics: Lyrics
    let position: TimeInterval
    var tint: Color = .white
    let onSeek: (TimeInterval) -> Void
    @AppStorage(Pref.lyricsFont) private var fontDesign = "system"
    @AppStorage(Pref.lyricsSize) private var fontSize = 22.0

    private var lineFont: Font { Pref.lyricsFont(id: fontDesign, size: fontSize) }

    var body: some View {
        if lyrics.isSynced {
            let current = lyrics.lineIndex(at: position)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(lineFont)
                                .foregroundStyle(i == current ? AnyShapeStyle(tint) : AnyShapeStyle(.white.opacity(0.35)))
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
                    .font(lineFont)
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
            // Album cover first (local cache); YouTube thumb as fallback.
            Group {
                if let img = Artwork.image(for: item.id.uuidString) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    AsyncImage(url: item.thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: item.isVideo ? "film" : "music.note")
                                .foregroundStyle(.secondary))
                    }
                }
            }
            .frame(width: 44, height: 44)
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
