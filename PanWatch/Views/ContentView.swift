import AVKit
import SwiftUI

/// The cook screen: camera picture filling the screen, step card top left, timers top
/// right, controls along the bottom, and the timer offer front and center.
struct ContentView: View {
    let session: CookSession

    var body: some View {
        ZStack {
            CameraStage(session: session)
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 12) {
                    if session.isMarkingPan {
                        MarkPanBanner(session: session)
                            .frame(maxWidth: .infinity)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            StepCard(session: session)
                            Spacer(minLength: 12)
                            TimerStack(session: session)
                        }
                    }
                    Spacer(minLength: 0)
                    ControlBar(session: session)
                }
                .padding(16)

                if session.showDebug {
                    DebugPanel(session: session)
                        .frame(width: 330)
                        .transition(.move(edge: .trailing))
                }
            }

            if let offer = session.suggestion {
                SuggestionCard(
                    offer: offer,
                    accept: { session.acceptSuggestion() },
                    dismiss: { session.dismissSuggestion() }
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            CameraStatusOverlay(status: session.cameraStatus)
        }
        .background(Color.black)
        .animation(.snappy, value: session.suggestion?.id)
        .animation(.snappy, value: session.showDebug)
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
