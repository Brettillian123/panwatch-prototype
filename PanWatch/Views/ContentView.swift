import AVKit
import SwiftUI

/// The cook screen: the camera picture fills the screen, the step panel sits top left,
/// timers top right, the bar and the Say line along the bottom, and the timer offer in
/// the middle. Panels are opaque Iron and the picture shows between them. Drawing the pan
/// box clears it to the picture, the strip and two buttons; nothing else hides the recipe.
struct ContentView: View {
    let session: CookSession
    @State private var showingSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if session.cameraOn {
                CameraStage(session: session)
                    .ignoresSafeArea()
                if session.suggestion != nil {
                    // The picture dims to 60% behind the offer.
                    Theme.iron.opacity(0.4)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }

            HStack(alignment: .top, spacing: Theme.gap) {
                VStack(spacing: Theme.tight) {
                    if session.isMarkingPan {
                        drawing
                    } else {
                        cooking
                    }
                    SayLine(session: session)
                }
                if session.showDebug && !session.isMarkingPan {
                    DebugPanel(session: session)
                        .frame(width: 330)
                        .transition(reduceMotion ? AnyTransition.opacity : .move(edge: .trailing))
                }
            }
            .padding(.top, Theme.gap)

            if let offer = session.suggestion {
                SuggestionCard(
                    offer: offer,
                    accept: { session.acceptSuggestion() },
                    dismiss: { session.dismissSuggestion() },
                    touched: { session.noteTouch() }
                )
                .id(offer.id)
                // Centered over everything but the Say line, which keeps showing what to say.
                .padding(.bottom, Theme.bigTarget + Theme.tight)
                .transition(reduceMotion ? AnyTransition.opacity : .scale(scale: 0.96).combined(with: .opacity))
            }

            if session.isChoosingRecipe {
                RecipePicker(session: session)
                    .transition(.opacity)
            }

            if showingSettings && !session.isChoosingRecipe {
                InterimSettings(session: session, close: { showingSettings = false })
                    .transition(.opacity)
            }

            if session.cameraOn {
                CameraStatusOverlay(status: session.cameraStatus)
            }
        }
        .overlay { SetupCheckView(check: session.setupCheck) } // Setup check
        .background(Theme.iron)
        .animation(Theme.entrance, value: session.suggestion?.id)
        .animation(Theme.motion, value: session.showDebug)
        .animation(Theme.motion, value: session.isChoosingRecipe)
        .animation(Theme.motion, value: session.isMarkingPan)
        .animation(Theme.motion, value: showingSettings)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .task { await session.start() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: session.settings) { session.applySettings() }
        // The volume buttons and Camera Control act as a physical "yes" / "next",
        // which works while the camera is running. Wet hands never need the screen.
        .onCameraCaptureEvent { event in
            if event.phase == .ended {
                session.hardwareButtonPressed()
            }
        }
    }

    /// Pan needed or not, the recipe stays: step panel left, timers right, bar below.
    private var cooking: some View {
        VStack(spacing: Theme.gap) {
            HStack(alignment: .top, spacing: Theme.gap) {
                StepCard(session: session)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Timers keep their width; the step text wraps, then scales, instead.
                TimerStack(session: session)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            ControlBar(session: session, openSettings: { showingSettings = true })
        }
        .transition(.opacity)
    }

    /// Drawing: the picture, one strip top left, Cancel and Start watching. Timers keep
    /// running and still speak; their rows come back when drawing ends.
    private var drawing: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            DrawingStrip(session: session)
            Spacer(minLength: 0)
            DrawPanBar(session: session)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}
