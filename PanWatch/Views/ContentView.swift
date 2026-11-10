import AVKit
import SwiftUI

/// The cook screen: the camera picture fills the screen, the step panel sits top left,
/// timers top right, the bar and the Say line along the bottom, and the timer offer in
/// the middle. Panels are opaque Iron and the picture shows between them. Drawing the pan
/// box clears it to the picture, the strip and two buttons; nothing else hides the recipe.
/// The old cook screen, shown by `CookScreen` until the cook piece rebuilds it. The app's
/// root, its screens and the tab bar are `RootView`.
struct ContentView: View {
    let session: CookSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        cookScreen
            .background(Theme.ground)
            .animation(Theme.entrance, value: session.suggestion?.id)
            .animation(Theme.motion, value: session.showDebug)
            .animation(Theme.motion, value: session.isMarkingPan)
    }

    /// The picture, the step panel, timers, the bar, the Say line and the offer. It stays
    /// under a menu so the camera keeps its picture.
    private var cookScreen: some View {
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

            if session.cameraOn {
                CameraStatusOverlay(status: session.cameraStatus)
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
            ControlBar(session: session, openSettings: { session.open(.settings) })
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

// MARK: - Menus

/// A full-screen menu over the cook screen: a 44 pt title, its rows, and along the bottom
/// the same Say line as the cook screen with a worded Done beside it, bottom right. Done
/// and "done" are the one way out.
struct MenuScreen<Content: View>: View {
    let session: CookSession
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(title)
                .font(Theme.reading)
                .foregroundStyle(Theme.flour)
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: Theme.gap) {
                SayLine(session: session)
                Button("Done") {
                    session.noteTouch()
                    session.closeMenu()
                }
                .buttonStyle(WordButtonStyle())
            }
        }
        .padding(.top, Theme.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.iron)
    }
}

/// The 1 px rule between list rows: Flour at 12%, never a box.
struct RowRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A whole list row as one target: pressed lifts it with the rule color, like a secondary
/// button, so a tap shows where it landed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.tight)
            .background(
                configuration.isPressed ? Theme.rule : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}
