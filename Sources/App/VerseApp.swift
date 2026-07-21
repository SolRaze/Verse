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
                // Foreground: reactivate the audio session (dead after a background suspend/
                // interruption, else nothing plays until relaunch) and start a Live Activity
                // that iOS blocked while backgrounded.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        coordinator.player.resumePlaybackIfNeeded()
                        coordinator.player.resumeLiveActivity()
                    }
                }
        }
    }
}
