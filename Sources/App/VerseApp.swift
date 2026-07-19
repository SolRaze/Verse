import SwiftUI

@main
struct VerseApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var coordinator: Coordinator

    init() {
        Pref.registerDefaults()
        let lib = LibraryStore()
        _library = StateObject(wrappedValue: lib)
        _coordinator = StateObject(wrappedValue: Coordinator(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(playlists)
                .environmentObject(coordinator)
        }
    }
}
