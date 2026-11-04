import AVKit
import SwiftUI

/// The cook screen: camera picture filling the screen, step card top left, timers top
/// right, controls along the bottom, and the timer offer front and center. Drawing the
/// pan box clears it to the picture; nothing else ever hides the recipe.
struct ContentView: View {
    let session: CookSession

    var body: some View {
        ZStack {
            if session.cameraOn {
                CameraStage(session: session)
                    .ignoresSafeArea()
            }

            if session.isMarkingPan {
                // The whole picture is free to draw on: one line at the top, two buttons below.
                VStack(spacing: 12) {
                    MarkPanBanner(session: session)
                    Spacer(minLength: 0)
                    DrawPanBar(session: session)
                }
                .padding(16)
                .transition(.opacity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            StepCard(session: session)
                            Spacer(minLength: 12)
                            TimerStack(session: session)
                                // Timers keep their width; the step text wraps and shrinks instead.
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer(minLength: 0)
                        if session.needsPan {
                            PanNeededStrip(session: session)
                        }
                        ControlBar(session: session)
                    }
                    .padding(16)

                    if session.showDebug {
                        DebugPanel(session: session)
                            .frame(width: 330)
                            .transition(.move(edge: .trailing))
                    }
                }
                .transition(.opacity)
            }

            if let offer = session.suggestion {
                SuggestionCard(
                    offer: offer,
                    accept: { session.acceptSuggestion() },
                    dismiss: { session.dismissSuggestion() },
                    touched: { session.noteTouch() }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if session.isChoosingRecipe {
                RecipePicker(session: session)
                    .transition(.opacity)
            }

            if session.cameraOn {
                CameraStatusOverlay(status: session.cameraStatus)
            }
        }
        .overlay { SetupCheckView(check: session.setupCheck) } // Setup check
        .background(Color.black)
        .animation(.snappy, value: session.suggestion?.id)
        .animation(.snappy, value: session.showDebug)
        .animation(.snappy, value: session.isChoosingRecipe)
        .animation(.snappy, value: session.isMarkingPan)
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
}
