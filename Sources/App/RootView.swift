import SwiftUI

/// The tab shell: Home + Library, with the things that outlive any one screen — the mini player
/// and the player sheet — owned here rather than duplicated per tab.
struct RootView: View {
    @EnvironmentObject var coordinator: Coordinator

    enum Tab { case home, library, create, search }
    @State private var tab: Tab = .home
    @AppStorage(Pref.theme) private var theme = ""
    @AppStorage(Pref.iPodMode) private var iPodMode = false

    var body: some View {
        // The accessory is ALWAYS attached (Apple-Music style, inbox-2): the dock must look the
        // same on boot as it does mid-song, so the bar shows a "Not Playing" idle state instead
        // of appearing when playback starts and resizing the dock.
        tabs
            .tabViewBottomAccessory { MiniPlayerBar(player: coordinator.player) }
            .sheet(isPresented: $coordinator.showPlayer) { PlayerView() }
            // iPod mode rides on top; MENU (or the toggle) leaves it.
            .fullScreenCover(isPresented: $iPodMode) {
                IPodView(player: coordinator.player)
            }
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
            // Create: a dock placeholder for planned making tools (stems, mixes) — faded, taps
            // just say "in the works" (2026-07-21 user request).
            SwiftUI.Tab("Create", systemImage: "plus.circle", value: Tab.create) {
                CreatePlaceholder()
            }
            // Settings pushes from Library's top-left gear (2026-07-21) — no dock tab.
            // role: .search puts this in the dock's own search pill, Files-app style.
            SwiftUI.Tab(value: Tab.search, role: .search) {
                SearchView()
            }
        }
    }
}

/// The Create tab's stand-in: the making tools (Stem Player, mixes) aren't built yet, so the tab
/// exists faded with a "coming" message instead of a working editor.
private struct CreatePlaceholder: View {
    var body: some View {
        ContentUnavailableView {
            Label("Create", systemImage: "plus.circle")
        } description: {
            Text("Making tools — Stem Player and mixes — are in the works. This tab is a placeholder until they land.")
        }
        .opacity(0.6)
    }
}
