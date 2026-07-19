import SwiftUI

/// The landing tab: a big `Music` title, search under it, then the smart shelves — playlists,
/// most-played albums, most-played tracks. Browsing and importing live in the Library tab.
///
/// "Album" here means a folder that directly holds tracks. This library has no album tag; the
/// folder tree is the organization, so a leaf folder is the closest true thing to an album.
struct HomeView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var coordinator: Coordinator
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                playlistsSection
                albumsSection
                tracksSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FolderPath.self) { fp in
                FolderView(path: fp.components)
            }
            .navigationDestination(for: RemotePlaylist.self) { pl in
                PlaylistDetailView(playlist: pl)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .overlay { emptyState }
        }
    }

    // MARK: shelves

    @ViewBuilder private var playlistsSection: some View {
        if !playlists.playlists.isEmpty {
            Section("Playlists") {
                ForEach(playlists.playlists) { pl in
                    NavigationLink(value: pl) { PlaylistRow(playlist: pl) }
                }
            }
        }
    }

    @ViewBuilder private var albumsSection: some View {
        let albums = library.mostPlayedAlbums()
        if !albums.isEmpty {
            Section("Most Played Albums") {
                ForEach(albums, id: \.path) { album in
                    NavigationLink(value: FolderPath(album.path)) {
                        FolderRow(name: album.path.last ?? "",
                                  count: library.descendants(of: album.path).count)
                    }
                }
            }
        }
    }

    @ViewBuilder private var tracksSection: some View {
        let tracks = library.mostPlayedTracks()
        if !tracks.isEmpty {
            Section("Most Played") {
                ForEach(tracks) { item in
                    Button { coordinator.play(item, in: tracks) } label: { ItemRow(item: item) }
                        .tint(.primary)
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
