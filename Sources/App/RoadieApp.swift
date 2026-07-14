import SwiftUI

@main
struct RoadieApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var coordinator: Coordinator

    init() {
        let lib = LibraryStore()
        _library = StateObject(wrappedValue: lib)
        _coordinator = StateObject(wrappedValue: Coordinator(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(coordinator)
        }
    }
}
