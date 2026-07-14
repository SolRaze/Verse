import SwiftUI

@main
struct RoadieApp: App {
    @StateObject private var player = Player()

    var body: some Scene {
        WindowGroup {
            // TODO: library + now-playing UI. See SPEC.md section 2.
            ContentView().environmentObject(player)
        }
    }
}

struct ContentView: View {
    var body: some View { Text("Roadie") }
}
