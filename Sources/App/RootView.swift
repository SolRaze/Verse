import SwiftUI

/// The tab shell: Home + Library, with the things that outlive any one screen — the mini player
/// and the player sheet — owned here rather than duplicated per tab.
struct RootView: View {
    @EnvironmentObject var coordinator: Coordinator

    enum Tab { case home, library, search }
    @State private var tab: Tab = .home
    @AppStorage(Pref.theme) private var theme = ""

    var body: some View {
        // The accessory is ALWAYS attached (Apple-Music style, inbox-2): the dock must look the
        // same on boot as it does mid-song, so the bar shows a "Not Playing" idle state instead
        // of appearing when playback starts and resizing the dock.
        tabs
            .tabViewBottomAccessory { MiniPlayerBar(player: coordinator.player) }
            .sheet(isPresented: $coordinator.showPlayer) { PlayerView() }
            .onChange(of: coordinator.deepLink) { _, link in
                if link != nil { tab = .library }
            }
            .tint(Pref.color(for: theme)) // monotone white default; Settings can retint
            .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            SwiftUI.Tab("Home", systemImage: "house.fill", value: Tab.home) {
                HomeView()
            }
            SwiftUI.Tab("Library", systemImage: "music.note.list", value: Tab.library) {
                LibraryView()
            }
            // role: .search puts this in the dock's own search pill, Files-app style.
            SwiftUI.Tab(value: Tab.search, role: .search) {
                SearchView()
            }
        }
    }
}
