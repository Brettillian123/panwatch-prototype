import AVKit
import SwiftUI
import UIKit

/// The app's root: the screen `CookSession.screen` names, the floating tab bar on the three
/// top-level screens, and the sheets over them. Cook mode stays underneath every other
/// screen, hidden, so it is there at once on the way back; its camera runs only while it
/// shows (`CameraGate`). Each screen is one file in `Views/Screens`.
struct RootView: View {
    let session: CookSession
    /// The recipe page's dark photo is under the status bar: the clock and battery go white.
    @State private var photoOnTop = true

    private var screen: AppScreen { session.screen }
    /// The screen under the help sheet, or the screen itself. Help opened in cook mode keeps cook mode under it.
    private var base: AppScreen {
        guard screen == .help else { return screen }
        return session.helpFrom == .help ? .cook : session.helpFrom
    }

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()

            CookScreen(session: session)
                .opacity(base == .cook ? 1 : 0)
                .accessibilityHidden(screen != .cook)
                .allowsHitTesting(screen == .cook)

            if base != .cook {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Theme.ground)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if base.showsTabBar {
                            FloatingTabBar(selected: base.tab) { tab in
                                session.noteTouch()
                                session.open(tab: tab)
                            }
                            .frame(maxWidth: .infinity)
                            // The list fades into the ground under the bar instead of showing through below it.
                            .background(alignment: .bottom) {
                                LinearGradient(
                                    colors: [Theme.ground.opacity(0), Theme.ground],
                                    startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)
                                )
                                .padding(.top, -Theme.space24)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .transition(.opacity)
            }

            if screen == .makeVoice {
                MakeVoiceSheet(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // The one place the voices' fetch is ever mentioned: a voice picked on cellular.
            if session.voiceFetch.askingMetered {
                NotOnWiFiSheet(fetch: session.voiceFetch)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if screen == .help {
                HelpOverlay(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.motion, value: screen)
        .statusBarHidden(base == .cook)
        .persistentSystemOverlays(base == .cook ? .hidden : .automatic)
        // Every color is a fixed token, so the scheme only picks the status bar's text color.
        .preferredColorScheme(base == .recipe && photoOnTop ? .dark : .light)
        .task {
            #if DEBUG
            if ScreenshotStage.requested != nil { return }
            #endif
            await session.start()
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            OrientationLock.apply(landscapeOnly: base.isLandscapeOnly)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: base.isLandscapeOnly) { _, landscapeOnly in
            OrientationLock.apply(landscapeOnly: landscapeOnly)
        }
        .onChange(of: session.settings) { session.applySettings() }
        // The volume buttons and Camera Control act as a physical "yes" / "next",
        // which works while the camera is running. Wet hands never need the screen.
        .onCameraCaptureEvent { event in
            if event.phase == .ended {
                session.hardwareButtonPressed()
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch base {
        case .recipes: HomeScreen(session: session)
        case .recipe: RecipeScreen(session: session, photoOnTop: $photoOnTop)
        case .recipeList: RecipeListScreen(session: session)
        case .voices: VoicesScreen(session: session)
        case .makeVoice:
            // The sheet sits over the screen it was opened from.
            if session.makeVoiceFrom == .profile { ProfileScreen(session: session) } else { VoicesScreen(session: session) }
        case .profile: ProfileScreen(session: session)
        case .help, .cook: EmptyView() // help is the sheet over `base`
        }
    }
}

/// Cook mode is landscape only; every other screen follows the phone, upside down aside.
/// The app delegate answers UIKit's question from `landscapeOnly`.
@MainActor
enum OrientationLock {
    private(set) static var landscapeOnly = false

    static var mask: UIInterfaceOrientationMask { landscapeOnly ? .landscape : .allButUpsideDown }

    static func apply(landscapeOnly: Bool) {
        self.landscapeOnly = landscapeOnly
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

#if DEBUG
/// `-uiScreen <name>` on the launch arguments, DEBUG builds only: the screen to stage for a screenshot.
enum ScreenshotStage {
    /// Every name `CookSession.stageForScreenshot` stages. A name missing here launches the app
    /// normally, so `start()` runs and the speech prompt covers that picture and the next one.
    static let names = ["recipes", "search", "recipeList", "recipe", "recipeLong", "cook", "offer", "voices", "makeVoice", "profile", "help"]

    static var requested: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: "-uiScreen"), at + 1 < arguments.count else { return nil }
        let name = arguments[at + 1]
        return names.contains(name) ? name : nil
    }
}
#endif
