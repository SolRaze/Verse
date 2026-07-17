import SwiftUI

/// The tab shell: Home + Library, with the things that outlive any one screen — the mini player
/// and the player sheet — owned here rather than duplicated per tab.
struct RootView: View {
    @EnvironmentObject var coordinator: Coordinator

    enum Tab { case home, library }
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            LibraryView()
                .tabItem { Label("Library", systemImage: "music.note.list") }
                .tag(Tab.library)
        }
        // Above the tab bar, present on every tab and every pushed screen — so it stays put
        // while browsing into folders instead of being re-laid-out per screen.
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .sheet(isPresented: $coordinator.showPlayer) { PlayerView() }
        .tint(.white)                 // monotone: one accent, no colored chrome
        .preferredColorScheme(.dark)
    }
}
