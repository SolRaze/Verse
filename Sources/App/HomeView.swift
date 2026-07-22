import SwiftUI
import UIKit

/// The landing tab: a big `Music` title, search under it, then the smart shelves — playlists,
/// most-played albums, most-played tracks. Browsing and importing live in the Library tab.
///
/// "Album" here means a folder that directly holds tracks. This library has no album tag; the
/// folder tree is the organization, so a leaf folder is the closest true thing to an album.
struct HomeView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    // Ordered, enabled-only shelf ids — hold a shelf header to move/remove (iPhone-home
    // style), the ellipsis menu adds shelves back and sizes the album grid.
    @AppStorage(Pref.homeSections) private var sectionsCSV = "now,playlists,albums,tracks"
    /// Per-shelf sizes, "id:size" pairs; anything absent = medium.
    @AppStorage(Pref.homeShelfSizes) private var shelfSizesCSV = ""
    @AppStorage(Pref.createUnlocked) private var createUnlocked = false
    @State private var path = NavigationPath()
    @State private var showCreate = false
    @State private var unlockFlash = false
    @State private var infoItem: LibraryItem?

    private func size(of id: String) -> String {
        for pair in shelfSizesCSV.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, kv[0] == Substring(id) { return String(kv[1]) }
        }
        return "medium"
    }

    private func setSize(_ id: String, _ s: String) {
        var pairs = shelfSizesCSV.split(separator: ",").map(String.init)
            .filter { !$0.hasPrefix(id + ":") }
        pairs.append(id + ":" + s)
        shelfSizesCSV = pairs.joined(separator: ",")
    }

    /// Rows a list shelf shows at each size.
    private func rowLimit(_ id: String) -> Int {
        switch size(of: id) { case "small": 3; case "large": 10; default: 6 }
    }

    static let allSections: [(id: String, name: String)] = [
        ("now", "Now Playing"), ("playlists", "Playlists"), ("albums", "Most Played Albums"),
        ("tracks", "Most Played"), ("recentAdded", "Recently Added"),
        ("recentPlayed", "Recently Played"),
    ]

    private var sectionIDs: [String] { sectionsCSV.split(separator: ",").map(String.init) }

    private func sectionName(_ id: String) -> String {
        Self.allSections.first { $0.id == id }?.name ?? id
    }

    private func removeSection(_ id: String) {
        sectionsCSV = sectionIDs.filter { $0 != id }.joined(separator: ",")
    }

    private func move(_ id: String, by delta: Int) {
        var ids = sectionIDs
        guard let i = ids.firstIndex(of: id) else { return }
        let j = i + delta
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        sectionsCSV = ids.joined(separator: ",")
    }

    @State private var editingHome = false

    /// Shelf header. Normal: hold → Edit Home Screen (iPhone-style, no toolbar button).
    /// Editing: minus badge + a size pill per shelf; add + done live in the edit section.
    private func shelfHeader(_ id: String) -> some View {
        HStack(spacing: 8) {
            if editingHome {
                Button { removeSection(id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
            }
            Text(sectionName(id))
            Spacer()
            if editingHome {
                // Cycle small → medium → large, widget-resize spirit.
                Button {
                    let next = switch size(of: id) {
                    case "small": "medium"; case "medium": "large"; default: "small"
                    }
                    setSize(id, next)
                } label: {
                    Text(size(of: id).capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        // The Spacer leaves most of the header empty; without an explicit hit shape the long
        // press only lands on the text glyphs, so "hold to edit" felt dead (2026-07-21). A
        // full-width content shape makes the whole header row press-able.
        .contentShape(Rectangle())
        .contextMenu {
            if !editingHome {
                Button { withAnimation(.snappy) { editingHome = true } } label: {
                    Label("Edit Home Screen", systemImage: "square.grid.2x2")
                }
                Button { move(id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
                Button { move(id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
                Button(role: .destructive) { removeSection(id) } label: {
                    Label("Remove from Home", systemImage: "minus.circle")
                }
            }
        }
    }

    /// Shown only while editing: add removed shelves back, then Done. (Toolbar stays empty —
    /// everything routes through holding a shelf, per the iPhone-home pattern.)
    @ViewBuilder private var editSection: some View {
        if editingHome {
            Section {
                ForEach(Self.allSections.filter { !sectionIDs.contains($0.id) }, id: \.id) { s in
                    Button {
                        sectionsCSV = (sectionIDs + [s.id]).joined(separator: ",")
                    } label: {
                        Label("Add \(s.name)", systemImage: "plus.circle.fill")
                    }
                }
                Button {
                    withAnimation(.snappy) { editingHome = false }
                } label: {
                    Text("Done").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(sectionIDs, id: \.self) { id in
                    switch id {
                    case "now": nowPlayingCard
                    case "playlists": playlistsSection
                    case "albums": albumsSection
                    case "tracks": tracksSection
                    case "recentAdded": recentlyAddedSection
                    case "recentPlayed": recentlyPlayedSection
                    default: EmptyView()
                    }
                }
                editSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AlbumRef.self) { AlbumPage(album: $0) }
            .navigationDestination(for: LocalPlaylist.self) { LocalPlaylistPage(playlist: $0) }
            .navigationDestination(for: FolderPath.self) { fp in
                FolderView(path: fp.components)
            }
            .navigationDestination(for: RemotePlaylist.self) { pl in
                PlaylistDetailView(playlist: pl)
            }
            // ponytail: an explicit Edit button (below) drives edit mode for now — the gesture
            // versions (firm-press / hold) fought the tiles' own taps. A non-blocking gesture is
            // planned (see plans/ipod-and-home-edit.md).
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editingHome ? "Done" : "Edit") {
                        withAnimation(.snappy) { editingHome.toggle() }
                    }
                }
            }
            .overlay { emptyState }
            // Hidden Create page. Locked: a triple-tap on the title strip unlocks it (with a
            // brief confirmation). Unlocked: a right-swipe from the left edge opens it.
            .overlay(alignment: .top) { if !createUnlocked { unlockStrip } }
            .overlay(alignment: .top) { if unlockFlash { unlockConfirmation } }
            .simultaneousGesture(revealSwipe)
            .fullScreenCover(isPresented: $showCreate) { CreatePage() }
            .modifier(TrackSheets(infoItem: $infoItem))
        }
    }

    /// A clear band over the large title that only listens for a triple-tap (single taps and
    /// scrolls fall through). Removed once unlocked so it never blocks anything again.
    private var unlockStrip: some View {
        Color.clear.frame(height: 90).contentShape(Rectangle())
            .onTapGesture(count: 3) {
                createUnlocked = true
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                withAnimation { unlockFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { unlockFlash = false }
                }
            }
    }

    private var unlockConfirmation: some View {
        Text("Deck unlocked — swipe right")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Left-edge right-swipe opens Create (only once unlocked). Edge-anchored + mostly-horizontal
    /// so it doesn't fight the List's vertical scroll.
    private var revealSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                guard createUnlocked, v.startLocation.x < 40,
                      v.translation.width > 90, abs(v.translation.height) < 60 else { return }
                showCreate = true
            }
    }

    // MARK: shelves

    @ViewBuilder private var playlistsSection: some View {
        if !playlists.playlists.isEmpty {
            Section(header: shelfHeader("playlists")) {
                ForEach(playlists.playlists.prefix(rowLimit("playlists")).map { $0 }) { pl in
                    NavigationLink(value: pl) { PlaylistRow(playlist: pl) }
                }
            }
        }
    }

    @ViewBuilder private var nowPlayingCard: some View {
        if coordinator.nowPlayingItem != nil || !coordinator.nowTitle.isEmpty {
            Section(header: shelfHeader("now")) {
                NowPlayingCard(player: coordinator.player, size: size(of: "now"))
                    .listRowBackground(Color.white.opacity(0.06))
            }
        }
    }

    /// Hold menu for an album tile: play or shuffle its tracks, or open it.
    @ViewBuilder private func albumMenu(_ name: String) -> some View {
        let tracks = library.items.filter { $0.albumKey == name }
        Button { if let f = tracks.first { coordinator.play(f, in: tracks) } } label: {
            Label("Play", systemImage: "play.fill")
        }
        Button { if let f = tracks.randomElement() { coordinator.play(f, in: tracks.shuffled()) } } label: {
            Label("Shuffle", systemImage: "shuffle")
        }
        Button { path.append(AlbumRef(name: name)) } label: {
            Label("Open Album", systemImage: "square.stack")
        }
    }

    /// Two-up grid of most-played albums (2026-07-21, was rows).
    @ViewBuilder private var albumsSection: some View {
        // Read here (not only inside albumCover) so a fetched cover re-renders the whole grid —
        // the helper's read alone didn't reliably register the dependency (2026-07-21).
        let _ = library.artworkVersion
        let albums = library.mostPlayedAlbums()
        if !albums.isEmpty {
            // Grid density is a user knob (Small 3-up / Medium 2-up / Large 1-up), Apple-widget
            // sizing spirit. Buttons push via the explicit path — a NavigationLink inside a
            // LazyVGrid row fired multiple pushes (the "swipe back three times" bug).
            let grid = size(of: "albums")
            let cols = grid == "small" ? 3 : grid == "large" ? 1 : 2
            Section(header: shelfHeader("albums")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                         count: cols), spacing: 14) {
                    ForEach(albums, id: \.name) { album in
                        Button { path.append(AlbumRef(name: album.name)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                albumCover(album.name)
                                Text(album.name)
                                    .font(grid == "small" ? .caption : .footnote.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(album.plays) play\(album.plays == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { albumMenu(album.name) }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func albumCover(_ name: String) -> some View {
        let _ = library.artworkVersion
        let src = library.items.first {
            $0.albumKey == name && Artwork.image(for: $0.id.uuidString) != nil
        }
        return Group {
            if let src, let img = Artwork.image(for: src.id.uuidString) {
                Image(uiImage: img).resizable().aspectRatio(1, contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "square.stack").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var recentlyAddedSection: some View {
        let recent = library.items
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
            .prefix(rowLimit("recentAdded")).map { $0 }
        if !recent.isEmpty {
            Section(header: shelfHeader("recentAdded")) {
                ForEach(recent) { item in
                    Button { coordinator.play(item, in: recent) } label: { ItemRow(item: item) }
                        .tint(.primary)
                        .contextMenu { ItemContextMenu(item: item, queue: recent, infoItem: $infoItem) }
                }
            }
        }
    }

    @ViewBuilder private var recentlyPlayedSection: some View {
        let recent = library.items.filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            .prefix(rowLimit("recentPlayed")).map { $0 }
        if !recent.isEmpty {
            Section(header: shelfHeader("recentPlayed")) {
                ForEach(recent) { item in
                    Button { coordinator.play(item, in: recent) } label: { ItemRow(item: item) }
                        .tint(.primary)
                        .contextMenu { ItemContextMenu(item: item, queue: recent, infoItem: $infoItem) }
                }
            }
        }
    }

    @ViewBuilder private var tracksSection: some View {
        let tracks = library.mostPlayedTracks(limit: rowLimit("tracks"))
        if !tracks.isEmpty {
            Section(header: shelfHeader("tracks")) {
                ForEach(tracks) { item in
                    Button { coordinator.play(item, in: tracks) } label: { ItemRow(item: item) }
                        .tint(.primary)
                        .contextMenu { ItemContextMenu(item: item, queue: tracks, infoItem: $infoItem) }
                }
            }
        }
    }

    /// Two different empty states: an empty library is a "go import something" problem, a library
    /// nobody has played yet is just waiting on data.
    @ViewBuilder private var emptyState: some View {
        if playlists.playlists.isEmpty,
           library.mostPlayedAlbums().isEmpty, library.mostPlayedTracks().isEmpty {
            if library.items.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet", systemImage: "music.note",
                    description: Text("Import a folder or paste a link from the Library tab."))
            } else {
                ContentUnavailableView(
                    "Nothing played yet", systemImage: "play.circle",
                    description: Text("Play something and your most-played albums and tracks show up here."))
            }
        }
    }
}

/// Standalone Home-shelf editor (#12): reached from the Library menu (above Settings). Adds,
/// removes and reorders the Home shelves via the same `Pref.homeSections` CSV the Home tab's
/// hold-to-edit uses, plus a suggestions list of shelves not on Home yet.
struct HomeLayoutEditor: View {
    @AppStorage(Pref.homeSections) private var sectionsCSV = "now,playlists,albums,tracks"
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []

    private func name(_ id: String) -> String {
        HomeView.allSections.first { $0.id == id }?.name ?? id
    }

    var body: some View {
        NavigationStack {
            List {
                Section("On Home") {
                    ForEach(ids, id: \.self) { id in Text(name(id)) }
                        .onMove { ids.move(fromOffsets: $0, toOffset: $1); save() }
                        .onDelete { ids.remove(atOffsets: $0); save() }
                }
                Section("Add to Home") {
                    ForEach(HomeView.allSections.filter { !ids.contains($0.id) }, id: \.id) { s in
                        Button { ids.append(s.id); save() } label: {
                            Label("Add \(s.name)", systemImage: "plus.circle.fill")
                        }
                    }
                    // Suggested-but-unbuilt shelves the user asked to surface here (#12).
                    Label("Locations — coming soon", systemImage: "map")
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .themedTint()
        .onAppear { ids = sectionsCSV.split(separator: ",").map(String.init) }
    }

    private func save() { sectionsCSV = ids.joined(separator: ",") }
}

/// Widget-shaped Now Playing card, shared by Home and the Queue sheet: cover, title,
/// play/pause, and the wave scrubber in a pill beneath (real audio when decodable).
struct NowPlayingCard: View {
    @EnvironmentObject var coordinator: Coordinator
    @ObservedObject var player: Player
    /// "small" = one compact row, no scrubber. "medium" = row + scrubber pill.
    /// "large" = big cover on top, widget-large spirit.
    var size: String = "medium"
    @State private var samples: [Float]?

    var body: some View {
        VStack(spacing: 8) {
            if size == "large" {
                Button { coordinator.showPlayer = true } label: {
                    artView
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Button { coordinator.showPlayer = true } label: {
                HStack(spacing: 12) {
                    if size != "large" {
                        artView
                            .frame(width: size == "small" ? 40 : 56,
                                   height: size == "small" ? 40 : 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if size != "small" {
                            Text("Now Playing").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(coordinator.nowTitle)
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !coordinator.nowArtist.isEmpty {
                            Text(coordinator.nowArtist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying
                            ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: size == "small" ? 28 : 36))
                    }
                    .buttonStyle(.plain)
                }
            }
            .tint(.primary)

            if size != "small", coordinator.engine == .vlc {
                WaveScrubber(samples: samples,
                             position: player.position,
                             duration: player.duration) { player.seek(to: $0) }
                    .frame(height: 18)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
            }
        }
        .task(id: player.current?.url) {
            samples = nil
            if let url = player.current?.url { samples = await Waveform.load(url: url) }
        }
    }

    @ViewBuilder private var artView: some View {
        if let art = player.current?.artwork {
            Image(uiImage: art).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}

/// The dock's search pill (Files-app style). Same flat title/artist match Home used to host.
struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                if !search.isEmpty {
                    let q = search.lowercased()
                    let hits = library.items.filter {
                        $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
                    }
                    Section("Results") {
                        ForEach(hits) { item in
                            Button { coordinator.play(item, in: hits) } label: { ItemRow(item: item) }
                                .tint(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            // System placement only. A drawer-pinned field fights the search tab's own bottom
            // field (two fields, clear button desyncs); the earlier "bad circle" was that fight,
            // not the minimize. SearchTests drives type -> clear -> retype to keep this honest.
            .searchable(text: $search)
        }
    }
}
