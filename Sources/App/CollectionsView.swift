import SwiftUI

/// The Apple-Music-shaped Library collections (inbox-2): Playlists / Artists / Albums / Songs
/// rows at the top of Library, each opening a big-title page with a sort menu top right.

enum CollectionKind: String, CaseIterable, Hashable {
    case playlists = "Playlists"
    case artists = "Artists"
    case albums = "Albums"
    case songs = "Songs"

    var icon: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        }
    }
}

/// Navigation value for an artist page.
struct ArtistRef: Hashable { let name: String }

struct CollectionPage: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    let kind: CollectionKind

    enum Sort: String, CaseIterable, Identifiable {
        case title = "Title", dateAdded = "Date Added", lastPlayed = "Last Played"
        case mostPlayed = "Most Played"
        var id: String { rawValue }
    }
    @State private var sort: Sort = .title

    var body: some View {
        List {
            switch kind {
            case .playlists: playlistRows
            case .artists: artistRows
            case .albums: albumRows
            case .songs: songRows
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kind.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Playlists sort by title only; the play-count sorts mean nothing for them.
            if kind != .playlists {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                }
            }
        }
        .overlay { emptyState }
    }

    // MARK: rows

    @ViewBuilder private var playlistRows: some View {
        ForEach(playlists.playlists.sorted { $0.title < $1.title }) { pl in
            NavigationLink(value: pl) { PlaylistRow(playlist: pl) }
                .swipeActions {
                    Button(role: .destructive) { playlists.remove(pl) } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
        }
    }

    @ViewBuilder private var artistRows: some View {
        let names = Set(library.items.map(\.artist).filter { !$0.isEmpty })
        ForEach(names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                id: \.self) { name in
            NavigationLink(value: ArtistRef(name: name)) {
                Label {
                    Text(name)
                } icon: {
                    Image(systemName: "music.mic").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var albumRows: some View {
        // "Album" = a folder that directly holds tracks, same meaning as Home.
        let albums = library.allFolders().filter { !library.children(of: $0).items.isEmpty }
        let sorted = sort == .mostPlayed
            ? albums.sorted {
                plays($0) > plays($1)
            }
            : albums.sorted { ($0.last ?? "") < ($1.last ?? "") }
        ForEach(sorted, id: \.self) { path in
            NavigationLink(value: FolderPath(path)) {
                FolderRow(name: path.last ?? "", count: library.descendants(of: path).count)
            }
        }
    }

    @ViewBuilder private var songRows: some View {
        let songs = sortedItems(library.items)
        ForEach(songs) { item in
            Button { coordinator.play(item, in: songs) } label: { ItemRow(item: item) }
                .tint(.primary)
        }
    }

    // MARK: sorting

    private func plays(_ path: [String]) -> Int {
        library.children(of: path).items.reduce(0) { $0 + $1.playCount }
    }

    private func sortedItems(_ items: [LibraryItem]) -> [LibraryItem] {
        switch sort {
        case .title: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded: items.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastPlayed: items.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .mostPlayed: items.sorted { $0.playCount > $1.playCount }
        }
    }

    @ViewBuilder private var emptyState: some View {
        let empty = switch kind {
        case .playlists: playlists.playlists.isEmpty
        case .artists: !library.items.contains { !$0.artist.isEmpty }
        case .albums: !library.allFolders().contains { !library.children(of: $0).items.isEmpty }
        case .songs: library.items.isEmpty
        }
        if empty {
            ContentUnavailableView("Nothing here yet", systemImage: kind.icon,
                                   description: Text("Import music and it will appear here."))
        }
    }
}

/// One artist's tracks, Home-shaped: big title + the same sort menu.
struct ArtistPage: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var coordinator: Coordinator
    let artist: ArtistRef

    @State private var sort: CollectionPage.Sort = .title

    var body: some View {
        let tracks = tracksSorted
        List {
            ForEach(tracks) { item in
                Button { coordinator.play(item, in: tracks) } label: { ItemRow(item: item) }
                    .tint(.primary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CollectionPage.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
            }
        }
    }

    private var tracksSorted: [LibraryItem] {
        let mine = library.items.filter { $0.artist == artist.name }
        return switch sort {
        case .title: mine.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .dateAdded: mine.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .lastPlayed: mine.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .mostPlayed: mine.sorted { $0.playCount > $1.playCount }
        }
    }
}
