import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var showingImporter = false
    @State private var linkText = ""
    @State private var editing: LibraryItem?
    @State private var infoItem: LibraryItem?
    @State private var moveRequest: MoveRequest?
    @State private var addingLink = false
    @State private var pasteSource: LinkSource?
    @State private var newFolderParent: [String]?     // nil = alert hidden
    @State private var newFolderName = ""
    @State private var renamingFolder: [String]?
    @State private var folderNewName = ""
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var path = NavigationPath()

    /// The link kinds the + menu offers. `host` seeds a hint; `addLink` still routes by URL.
    enum LinkSource: String, Identifiable {
        case youtube = "YouTube", spotify = "Spotify", soundcloud = "SoundCloud"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .youtube: "play.rectangle.fill"
            case .spotify: "circle.grid.cross.fill"
            case .soundcloud: "cloud.fill"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            // The selection binding and the editMode environment each install a pan gesture, and
            // `navigationDestination` below inherits this chain — so an always-on editMode here
            // leaked into FolderView and ate its first interactive pop no matter what FolderView
            // did locally. Wire both up only once the user actually enters Select.
            Group {
                if editMode == .active {
                    List(selection: $selection) { rootRows }
                        .environment(\.editMode, $editMode)
                } else {
                    List { rootRows }
                }
            }
            .listStyle(.insetGrouped)
            // No search here (inbox-2) — the dock's search pill owns search now.
            // Same shape as Home: big label on top.
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FolderPath.self) { fp in
                FolderView(path: fp.components)
            }
            .navigationDestination(for: RemotePlaylist.self) { pl in
                PlaylistDetailView(playlist: pl)
            }
            .navigationDestination(for: CollectionKind.self) { CollectionPage(kind: $0) }
            .navigationDestination(for: ArtistRef.self) { ArtistPage(artist: $0) }
            // Player-burger deep-links. onAppear covers the tab being built cold for the link
            // (a lazy TabView child misses an onChange that fired before it existed).
            .onChange(of: coordinator.deepLink) { _, _ in consumeDeepLink() }
            .onAppear(perform: consumeDeepLink)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode == .active {
                        Button("Done") { editMode = .inactive; selection = [] }
                    }
                }
                // One menu, not two: the import (+) and options (burger) menus are folded
                // together under three dots.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingImporter = true } label: {
                            Label("Open from Files", systemImage: "folder")
                        }
                        ForEach([LinkSource.youtube, .spotify, .soundcloud]) { src in
                            Button { linkText = ""; pasteSource = src } label: {
                                Label(src.rawValue, systemImage: src.icon)
                            }
                        }
                        Divider()
                        Button { editMode = .active } label: { Label("Select", systemImage: "checkmark.circle") }
                        Button { newFolderName = ""; newFolderParent = [] } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        SortMenu()
                    } label: {
                        // Bare dots, no circle (inbox-2).
                        Image(systemName: "ellipsis")
                    }
                    // Stable hook for UI tests — SwiftUI labels an ellipsis menu "More", which
                    // isn't a contract.
                    .accessibilityIdentifier("libraryMenu")
                    .disabled(addingLink)
                }
            }
            .overlay { emptyState }
            .overlay { if addingLink || coordinator.busy { ProgressView().controlSize(.large) } }
            // The mini player lives on the tab shell (RootView), not here — it has to survive
            // navigation and tab switches. Only the edit-mode bar is this screen's business.
            .safeAreaInset(edge: .bottom) {
                if editMode == .active {
                    BatchBar(selection: $selection, editMode: $editMode, moveRequest: $moveRequest)
                }
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.folder],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.add(pickedURLs: urls) }
            }
            .alert("Paste \(pasteSource?.rawValue ?? "") link", isPresented: .init(
                get: { pasteSource != nil },
                set: { if !$0 { pasteSource = nil } })
            ) {
                TextField("URL", text: $linkText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add") { addLink() }
                Button("Cancel", role: .cancel) { linkText = "" }
            }
            .alert("Something failed", isPresented: .init(
                get: { coordinator.lastError != nil },
                set: { if !$0 { coordinator.lastError = nil } })
            ) { Button("OK", role: .cancel) {} } message: {
                Text(coordinator.lastError ?? "")
            }
            .alert("New Folder", isPresented: .init(
                get: { newFolderParent != nil }, set: { if !$0 { newFolderParent = nil } })
            ) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    library.createFolder(named: newFolderName, in: newFolderParent ?? [])
                    newFolderName = ""; newFolderParent = nil
                }
                Button("Cancel", role: .cancel) { newFolderName = ""; newFolderParent = nil }
            }
            .alert("Rename Folder", isPresented: .init(
                get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })
            ) {
                TextField("Name", text: $folderNewName)
                Button("Rename") {
                    if let p = renamingFolder { library.renameFolder(p, to: folderNewName) }
                    renamingFolder = nil
                }
                Button("Cancel", role: .cancel) { renamingFolder = nil }
            }
            // The player sheet is app-level (RootView) — a play started from the Home tab has to
            // present it too.
            .sheet(item: $editing) { item in EditItemSheet(item: item) }
            .sheet(item: $infoItem) { item in InfoSheet(item: item) }
            .sheet(item: $moveRequest) { req in MoveSheet(request: req) }
        }
        .tint(.white)                 // monotone: one accent, no colored chrome
        .preferredColorScheme(.dark)
    }

    // MARK: sections

    @ViewBuilder private var rootRows: some View {
        collectionsSection
        folderContents(path: [])          // top-level folders + loose items
    }

    /// Apple-Music-style entry rows: Playlists / Artists / Albums / Songs (inbox-2). Remote
    /// playlists moved off the root into the Playlists page.
    private var collectionsSection: some View {
        Section {
            ForEach(CollectionKind.allCases, id: \.self) { kind in
                NavigationLink(value: kind) {
                    Label {
                        Text(kind.rawValue)
                    } icon: {
                        Image(systemName: kind.icon).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Replace the stack with the deep-linked destination. `folder([])` = a loose root track:
    /// popping to the root is the whole navigation.
    private func consumeDeepLink() {
        guard let link = coordinator.deepLink else { return }
        coordinator.deepLink = nil
        path = NavigationPath()
        switch link {
        case .folder(let components):
            if !components.isEmpty { path.append(FolderPath(components)) }
        case .artist(let name):
            path.append(ArtistRef(name: name))
        }
    }

    /// Folders + items directly inside `path`, rendered as a section. Used at the root.
    @ViewBuilder private func folderContents(path: [String]) -> some View {
        let child = library.children(of: path)
        if !child.folders.isEmpty || !child.items.isEmpty {
            Section("Library") {
                ForEach(child.folders, id: \.self) { name in
                    NavigationLink(value: FolderPath(path + [name])) {
                        FolderRow(name: name, count: library.descendants(of: path + [name]).count)
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.removeFolder(path + [name]) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu { folderMenu(path + [name]) }
                }
                ForEach(child.items) { item in itemButton(item, queue: child.items) }
            }
        }
    }

    private func itemButton(_ item: LibraryItem, queue: [LibraryItem]) -> some View {
        Button {
            coordinator.play(item, in: queue)
        } label: {
            ItemRow(item: item)
        }
        .tag(item.id)
        .tint(.primary)
        .swipeActions {
            Button(role: .destructive) { library.remove(item) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
        }
        .contextMenu { itemMenu(item, queue: queue) }
    }

    @ViewBuilder private func folderMenu(_ path: [String]) -> some View {
        FolderContextMenu(path: path, renamingFolder: $renamingFolder,
                          folderNewName: $folderNewName, newFolderParent: $newFolderParent,
                          moveRequest: $moveRequest)
    }

    @ViewBuilder private func itemMenu(_ item: LibraryItem, queue: [LibraryItem]) -> some View {
        ItemContextMenu(item: item, queue: queue, editing: $editing,
                        infoItem: $infoItem, moveRequest: $moveRequest)
    }

    @ViewBuilder private var emptyState: some View {
        if library.items.isEmpty && playlists.playlists.isEmpty {
            ContentUnavailableView(
                "Nothing here yet", systemImage: "folder",
                description: Text("Import a folder with the button above, or paste a YouTube, Spotify, or SoundCloud link."))
        }
    }

    private func addLink() {
        guard let url = URL(string: linkText.trimmingCharacters(in: .whitespaces)),
              url.host != nil else { return }
        linkText = ""
        addingLink = true
        Task {
            defer { addingLink = false }
            do {
                try await playlists.add(url: url)
            } catch PlaylistFetcher.FetchError.unsupportedURL where url.host?.contains("yout") == true {
                library.add(youtubeURL: url)   // plain video link
            } catch {
                coordinator.lastError = error.localizedDescription
            }
        }
    }
}

/// Navigable folder path. A plain `[String]` can't be a `navigationDestination` value type without
/// clashing with other array destinations, so wrap it.
struct FolderPath: Hashable {
    let components: [String]
    init(_ components: [String]) { self.components = components }
}

// MARK: - Folder screen (recursive)

struct FolderView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var editing: LibraryItem?
    @State private var infoItem: LibraryItem?
    @State private var moveRequest: MoveRequest?
    @State private var newFolderParent: [String]?
    @State private var newFolderName = ""
    @State private var renamingFolder: [String]?
    @State private var folderNewName = ""
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    let path: [String]

    @ViewBuilder private func rows(_ child: (folders: [String], items: [LibraryItem])) -> some View {
        ForEach(child.folders, id: \.self) { name in
            NavigationLink(value: FolderPath(path + [name])) {
                FolderRow(name: name, count: library.descendants(of: path + [name]).count)
            }
            .swipeActions {
                Button(role: .destructive) { library.removeFolder(path + [name]) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                FolderContextMenu(path: path + [name], renamingFolder: $renamingFolder,
                                  folderNewName: $folderNewName, newFolderParent: $newFolderParent,
                                  moveRequest: $moveRequest)
            }
        }
        ForEach(child.items) { item in
            Button { coordinator.play(item, in: child.items) } label: { ItemRow(item: item) }
                .tag(item.id)
                .tint(.primary)
                .swipeActions {
                    Button(role: .destructive) { library.remove(item) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
                }
                .contextMenu {
                    ItemContextMenu(item: item, queue: child.items, editing: $editing,
                                    infoItem: $infoItem, moveRequest: $moveRequest)
                }
        }
    }

    var body: some View {
        let child = library.children(of: path)
        // Plain List with NO editMode environment while browsing — both a selection binding and
        // an editMode binding install pan gestures that fight the interactive swipe-back
        // (it took two swipes). Only wire them up once the user actually enters Select.
        Group {
            if editMode == .active {
                List(selection: $selection) { rows(child) }
                    .environment(\.editMode, $editMode)
            } else {
                List { rows(child) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(path.last ?? "Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .active {
                    Button("Done") { editMode = .inactive; selection = [] }
                } else {
                    Menu {
                        Button {
                            let all = library.descendants(of: path)
                            if let first = all.first { coordinator.play(first, in: all) }
                        } label: { Label("Play", systemImage: "play.fill") }
                        Button { editMode = .active } label: { Label("Select", systemImage: "checkmark.circle") }
                        Button { newFolderName = ""; newFolderParent = path } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        SortMenu()
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .alert("New Folder", isPresented: .init(
            get: { newFolderParent != nil }, set: { if !$0 { newFolderParent = nil } })
        ) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                library.createFolder(named: newFolderName, in: newFolderParent ?? path)
                newFolderName = ""; newFolderParent = nil
            }
            Button("Cancel", role: .cancel) { newFolderName = ""; newFolderParent = nil }
        }
        .alert("Rename Folder", isPresented: .init(
            get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })
        ) {
            TextField("Name", text: $folderNewName)
            Button("Rename") {
                if let p = renamingFolder { library.renameFolder(p, to: folderNewName) }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode == .active {
                BatchBar(selection: $selection, editMode: $editMode, moveRequest: $moveRequest)
            }
        }
        .sheet(item: $editing) { item in EditItemSheet(item: item) }
        .sheet(item: $infoItem) { item in InfoSheet(item: item) }
        .sheet(item: $moveRequest) { req in MoveSheet(request: req) }
    }
}

// MARK: - Rows

/// "1 item" / "12 items".
func itemCountText(_ n: Int) -> String { "\(n) item\(n == 1 ? "" : "s")" }

struct FolderRow: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2).foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                Text(itemCountText(count)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ItemRow: View {
    // Observe the store so rows re-render when background artwork extraction finishes.
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    let item: LibraryItem

    private var isNowPlaying: Bool { coordinator.nowPlayingItemID == item.id }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                    .foregroundStyle(isNowPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                if !item.artist.isEmpty {
                    Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isNowPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: coordinator.player.isPlaying)
            }
        }
    }

    @ViewBuilder private var thumbnail: some View {
        let _ = library.artworkVersion   // re-render trigger
        if let local = Artwork.image(for: item.id.uuidString) {
            Image(uiImage: local).resizable().scaledToFill()
        } else if let remote = item.thumbnailURL {
            AsyncImage(url: remote) { $0.resizable().scaledToFill() } placeholder: { placeholder }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            .overlay(Image(systemName: item.isVideo ? "film" : "music.note")
                .foregroundStyle(.secondary))
    }
}

struct PlaylistRow: View {
    let playlist: RemotePlaylist

    private var icon: String {
        switch playlist.kind {
        case .youtubePlaylist, .youtubeChannel: "play.rectangle.fill"
        case .spotify: "circle.grid.cross.fill"
        case .soundcloud: "cloud.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2).foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title).lineLimit(1)
                Text(itemCountText(playlist.entries.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Remote playlist detail

struct PlaylistDetailView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var refreshing = false
    let playlist: RemotePlaylist

    private var current: RemotePlaylist {
        playlists.playlists.first { $0.id == playlist.id } ?? playlist
    }

    var body: some View {
        List {
            ForEach(Array(current.entries.enumerated()), id: \.offset) { i, entry in
                Button {
                    coordinator.play(current, at: i)
                } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing).monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline).lineLimit(1)
                            if !entry.artist.isEmpty {
                                Text(entry.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if PlaylistMatcher.match(entry, in: library.items) != nil {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.primary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if refreshing {
                    ProgressView()
                } else {
                    Button {
                        refreshing = true
                        Task {
                            defer { refreshing = false }
                            do { try await playlists.refresh(current) }
                            catch { coordinator.lastError = error.localizedDescription }
                        }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }
}

// MARK: - Mini player

/// Apple Music's pill: art left, title middle, play + forward right. Always present (idle =
/// "Not Playing") so the dock never changes shape when playback starts.
struct MiniPlayerBar: View {
    @EnvironmentObject var coordinator: Coordinator
    // Observed directly, not through coordinator: position ticks drive the wave scrubber.
    @ObservedObject var player: Player
    @AppStorage(Pref.waveInMini) private var waveInMini = false
    @State private var samples: [Float]?

    private var idle: Bool { coordinator.nowTitle.isEmpty }

    private var playing: Bool {
        coordinator.engine == .vlc ? player.isPlaying : coordinator.airPlayer.isPlaying
    }

    /// The Settings toggle, and only where a wave means anything (VLC path, something playing).
    private var showWave: Bool { waveInMini && !idle && coordinator.engine == .vlc }

    var body: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(idle ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(idle ? "Not Playing" : coordinator.nowTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(idle ? .secondary : .primary)
                    .lineLimit(1)
                if showWave {
                    // Takes the artist line's slot so the pill never changes height.
                    WaveScrubber(samples: samples,
                                 position: player.position,
                                 duration: player.duration) { player.seek(to: $0) }
                        .frame(height: 12)
                } else if !idle, !coordinator.nowArtist.isEmpty {
                    Text(coordinator.nowArtist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .task(id: player.current?.url) {
                samples = nil
                guard waveInMini, let url = player.current?.url else { return }
                samples = await Waveform.load(url: url)
            }
            Spacer(minLength: 0)

            Button {
                if coordinator.engine == .vlc {
                    player.toggle()
                } else {
                    playing ? coordinator.airPlayer.player.pause() : coordinator.airPlayer.player.play()
                }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
            }
            .disabled(idle)
            Button { coordinator.skip(1) } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .disabled(idle)
        }
        .opacity(idle ? 0.7 : 1)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        // No background: the tab bar's bottom accessory is already a glass capsule, so drawing
        // another material capsule in here nests one inside the other.
        .contentShape(Capsule())
        .onTapGesture { if !idle { coordinator.showPlayer = true } }
    }

    @ViewBuilder private var artwork: some View {
        if let art = coordinator.player.current?.artwork {
            Image(uiImage: art).resizable().scaledToFill()
        } else if let thumb = coordinator.nowPlayingItem?.thumbnailURL {
            AsyncImage(url: thumb) { $0.resizable().scaledToFill() } placeholder: { artPlaceholder }
        } else {
            artPlaceholder
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(0.1))
            .overlay(Image(systemName: "music.note").font(.caption).foregroundStyle(.secondary))
    }
}


// MARK: -

/// Shared context menu for an item — identical on the root and inside folders.
struct ItemContextMenu: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    let item: LibraryItem
    let queue: [LibraryItem]
    @Binding var editing: LibraryItem?
    @Binding var infoItem: LibraryItem?
    @Binding var moveRequest: MoveRequest?

    var body: some View {
        Button { coordinator.play(item, in: queue) } label: { Label("Play", systemImage: "play.fill") }
        Menu {
            Button { coordinator.playNext(item) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { coordinator.playLast(item) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
        } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
        Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
        if case .file = item.source {
            Button { Task { await library.fetchMetadata(item) } } label: {
                Label("Fetch Metadata", systemImage: "wand.and.stars")
            }
        }
        Button {
            moveRequest = MoveRequest(title: "Move \(item.title)", excluding: []) {
                library.move(item, to: $0)
            }
        } label: { Label("Move to…", systemImage: "folder") }
        Button { infoItem = item } label: { Label("Info", systemImage: "info.circle") }
        if let url = library.resolveURL(item) {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) { library.remove(item) } label: { Label("Delete", systemImage: "trash") }
    }
}

/// Shared context menu for a folder.
struct FolderContextMenu: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    let path: [String]
    @Binding var renamingFolder: [String]?
    @Binding var folderNewName: String
    @Binding var newFolderParent: [String]?
    @Binding var moveRequest: MoveRequest?

    var body: some View {
        Button {
            let all = library.descendants(of: path)
            if let f = all.first { coordinator.play(f, in: all) }
        } label: { Label("Play", systemImage: "play.fill") }
        Button { newFolderParent = path } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        Button { folderNewName = path.last ?? ""; renamingFolder = path } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            moveRequest = MoveRequest(title: "Move \(path.last ?? "")", excluding: path) {
                library.moveFolder(path, under: $0)
            }
        } label: { Label("Move to…", systemImage: "folder") }
        Button(role: .destructive) { library.removeFolder(path) } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

/// Sort field + order picker, shared by every browsing screen.
struct SortMenu: View {
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        Menu {
            Picker("Sort By", selection: $library.sortField) {
                ForEach(SortField.allCases) { f in Label(f.rawValue, systemImage: f.icon).tag(f) }
            }
            Divider()
            Picker("Order", selection: $library.sortAscending) {
                Label("Ascending", systemImage: "arrow.up").tag(true)
                Label("Descending", systemImage: "arrow.down").tag(false)
            }
        } label: { Label("Sort By", systemImage: "arrow.up.arrow.down") }
    }
}

/// Bottom bar shown in select mode: batch delete / move.
struct BatchBar: View {
    @EnvironmentObject var library: LibraryStore
    @Binding var selection: Set<UUID>
    @Binding var editMode: EditMode
    @Binding var moveRequest: MoveRequest?

    var body: some View {
        HStack {
            Button(role: .destructive) {
                library.remove(selection); selection = []; editMode = .inactive
            } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)
            Spacer()
            Text(selection.isEmpty ? "Select Items" : "\(selection.count) selected")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button {
                let ids = selection
                moveRequest = MoveRequest(title: "Move \(ids.count)", excluding: []) { path in
                    library.move(ids, to: path); selection = []; editMode = .inactive
                }
            } label: { Label("Move", systemImage: "folder") }
                .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.bar)
    }
}

/// A pending "move to a folder" action — the picker calls `onPick` with the chosen path.
struct MoveRequest: Identifiable {
    let id = UUID()
    let title: String
    let excluding: [String]        // hide this folder subtree (can't move into itself)
    let onPick: ([String]) -> Void
}

/// Pick a destination folder, or make a new one on the spot. Works for a single item, a batch,
/// or a folder — the caller supplies what to do with the picked path.
private struct MoveSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newFolderName = ""
    let request: MoveRequest

    private var destinations: [[String]] {
        library.allFolders().filter { !$0.starts(with: request.excluding) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New folder name", text: $newFolderName)
                        Button("Create") {
                            let name = newFolderName.trimmingCharacters(in: .whitespaces)
                            library.createFolder(named: name, in: [])
                            pick([name])
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Move to") {
                    Button { pick([]) } label: { Label("Library (root)", systemImage: "house") }
                    ForEach(destinations, id: \.self) { path in
                        Button { pick(path) } label: {
                            Label(path.joined(separator: " / "), systemImage: "folder")
                        }
                    }
                }
            }
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(.white)
    }

    private func pick(_ path: [String]) { request.onPick(path); dismiss() }
}

/// File-manager "Get Info" panel.
struct InfoSheet: View {      // shared with the player's burger menu
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var info: LibraryStore.FileInfo?
    let item: LibraryItem

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Title", value: item.title)
                if !item.artist.isEmpty { LabeledContent("Artist", value: item.artist) }
                if let info {
                    LabeledContent("Where", value: info.folder)
                    LabeledContent("Name", value: info.location)
                    LabeledContent("Kind", value: info.kind)
                    if let s = info.size {
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
                    }
                    if let d = info.duration {
                        LabeledContent("Duration", value: durationString(d))
                    }
                    if let a = info.added {
                        LabeledContent("Added", value: a.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(.white)
        .task { info = await library.info(for: item) }
    }

    private func durationString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60)
                         : String(format: "%d:%02d", s/60, s%60)
    }
}

private struct EditItemSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var item: LibraryItem

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $item.title)
                TextField("Artist", text: $item.artist)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { library.update(item); dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(220)])
        .tint(.white)
    }
}
