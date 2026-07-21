import SwiftUI

@main
struct VerseApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var playlists = PlaylistStore()
    @StateObject private var coordinator: Coordinator
    @Environment(\.scenePhase) private var scenePhase

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
                // Foreground: start a Live Activity that iOS blocked while backgrounded.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { coordinator.player.resumeLiveActivity() }
                }
        }
    }
}
