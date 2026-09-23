import SwiftUI

@main
struct PanWatchApp: App {
    @State private var session = CookSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}
