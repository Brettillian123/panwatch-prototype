import SwiftUI

@main
struct PanWatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: CookSession

    init() {
        RecipeIndex.preload()
        let session = CookSession()
        #if DEBUG
        if let name = ScreenshotStage.requested { session.stageForScreenshot(name) }
        #endif
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
    }
}
