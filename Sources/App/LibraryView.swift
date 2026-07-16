import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var showingImporter = false
    @State private var linkText = ""
    @State private var search = ""
    @State private var editing: LibraryItem?
    @State private var addingLink = false
    @State private var pasteSource: LinkSource?

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
        NavigationStack {
            List {
                if search.isEmpty {
                    remotePlaylistsSection
                    folderContents(path: [])          // top-level folders + loose items
                } else {
                    searchResults
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search your library")
            .navigationTitle("Library")
            .navigationDestination(for: FolderPath.self) { fp in
                FolderView(path: fp.components)
            }
            .navigationDestination(for: RemotePlaylist.self) { pl in
                PlaylistDetailView(playlist: pl)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingImporter = true } label: {
                            Label("Open from Files", systemImage: "folder")
                        }
                        Divider()
                        ForEach([LinkSource.youtube, .spotify, .soundcloud]) { src in
                            Button { linkText = ""; pasteSource = src } label: {
                                Label(src.rawValue, systemImage: src.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(addingLink)
                }
            }
            .overlay { emptyState }
            .overlay { if addingLink || coordinator.busy { ProgressView().controlSize(.large) } }
            .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
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
            .sheet(isPresented: $coordinator.showPlayer) { PlayerView() }
            .sheet(item: $editing) { item in EditItemSheet(item: item) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: sections

    @ViewBuilder private var remotePlaylistsSection: some View {
        if !playlists.playlists.isEmpty {
            Section("Playlists") {
                ForEach(playlists.playlists) { pl in
                    NavigationLink(value: pl) { PlaylistRow(playlist: pl) }
                        .swipeActions {
                            Button(role: .destructive) { playlists.remove(pl) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
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
                    .contextMenu {
                        Button {
                            let all = library.descendants(of: path + [name])
                            if let f = all.first { coordinator.play(f, in: all) }
                        } label: { Label("Play", systemImage: "play.fill") }
                        Button(role: .destructive) { library.removeFolder(path + [name]) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                ForEach(child.items) { item in itemButton(item, queue: child.items) }
            }
        }
    }

    private var searchResults: some View {
        let q = search.lowercased()
        let hits = library.items.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
        return Section("Results") {
            ForEach(hits) { item in itemButton(item, queue: hits) }
        }
    }

    private func itemButton(_ item: LibraryItem, queue: [LibraryItem]) -> some View {
        Button {
            coordinator.play(item, in: queue)
        } label: {
            ItemRow(item: item)
        }
        .tint(.primary)
        .swipeActions {
            Button(role: .destructive) { library.remove(item) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
                .tint(.orange)
        }
        .contextMenu {
            Button { coordinator.play(item, in: queue) } label: { Label("Play", systemImage: "play.fill") }
            Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { library.remove(item) } label: { Label("Delete", systemImage: "trash") }
        }
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

private struct FolderView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var editing: LibraryItem?
    let path: [String]

    var body: some View {
        let child = library.children(of: path)
        List {
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
                    Button {
                        let all = library.descendants(of: path + [name])
                        if let f = all.first { coordinator.play(f, in: all) }
                    } label: { Label("Play", systemImage: "play.fill") }
                    Button(role: .destructive) { library.removeFolder(path + [name]) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            ForEach(child.items) { item in
                Button { coordinator.play(item, in: child.items) } label: { ItemRow(item: item) }
                    .tint(.primary)
                    .swipeActions {
                        Button(role: .destructive) { library.remove(item) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button { coordinator.play(item, in: child.items) } label: { Label("Play", systemImage: "play.fill") }
                        Button { editing = item } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { library.remove(item) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(path.last ?? "Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Play the whole subtree as one queue.
                Button {
                    let all = library.descendants(of: path)
                    if let first = all.first { coordinator.play(first, in: all) }
                } label: { Image(systemName: "play.fill") }
            }
        }
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .sheet(item: $editing) { item in EditItemSheet(item: item) }
    }
}

// MARK: - Rows

/// "1 item" / "12 items".
func itemCountText(_ n: Int) -> String { "\(n) item\(n == 1 ? "" : "s")" }

private struct FolderRow: View {
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

private struct ItemRow: View {
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

private struct PlaylistRow: View {
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

private struct PlaylistDetailView: View {
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
                                .font(.footnote).foregroundStyle(.green)
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
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }
}

// MARK: - Mini player

private struct MiniPlayerBar: View {
    @EnvironmentObject var coordinator: Coordinator

    var body: some View {
        if !coordinator.nowTitle.isEmpty { MiniPlayerContent() }
    }
}

private struct MiniPlayerContent: View {
    @EnvironmentObject var coordinator: Coordinator

    private var playing: Bool {
        coordinator.engine == .vlc ? coordinator.player.isPlaying : coordinator.airPlayer.isPlaying
    }

    var body: some View {
        let _ = coordinator.player.isPlaying   // observe VLC state
        HStack(spacing: 12) {
            Image(systemName: coordinator.engine == .airplay ? "film" : "music.note")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(coordinator.nowTitle).font(.footnote.weight(.semibold)).lineLimit(1)
                if !coordinator.nowArtist.isEmpty {
                    Text(coordinator.nowArtist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Button {
                if coordinator.engine == .vlc {
                    coordinator.player.toggle()
                } else {
                    playing ? coordinator.airPlayer.player.pause() : coordinator.airPlayer.player.play()
                }
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill").font(.title3)
            }
            Button { coordinator.skip(1) } label: {
                Image(systemName: "forward.fill").font(.body)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { coordinator.showPlayer = true }
    }
}

// MARK: -

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
    }
}
