import SwiftUI
import UIKit

/// Cook mode, landscape only. The camera sits in a 290 pt box on the side of the Dynamic
/// Island; the step and the buttons are the main thing, in the column beside it: the top row
/// (where the cook is, help, close), the step in a fixed 120 pt slot, then the timer card and
/// Back / Next step, or the timer offer in their place. Drawing the pan box grows the camera
/// box and shrinks the column to one caption and two buttons. The ground is `Theme.ground`;
/// nothing is drawn over the picture except the one chip.
struct CookScreen: View {
    let session: CookSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTimers = false
    @State private var confirmLeave = false
    /// The Dynamic Island is on the leading edge (the phone's top to the left).
    @State private var islandLeading = true

    private var drawing: Bool { session.isMarkingPan }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            // The island's side keeps its safe area (62 on this phone); the other side is 20 from the edge.
            let leading = islandLeading ? max(insets.leading, Theme.margin) : Theme.margin
            let trailing = islandLeading ? Theme.margin : max(insets.trailing, Theme.margin)
            let width = proxy.size.width + insets.leading + insets.trailing
            let inner = width - leading - trailing
            let drawColumn: CGFloat = 220
            let boxWidth = drawing ? inner - Theme.space24 - drawColumn : 290

            HStack(alignment: .top, spacing: Theme.space24) {
                CookCameraBox(session: session, drawing: drawing, openDrawing: openDrawing)
                    .frame(width: boxWidth)
                Group {
                    if drawing {
                        drawingColumn.transition(.opacity)
                    } else {
                        column.transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 20)
            .padding(.bottom, 21)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(width: width, height: proxy.size.height + insets.top + insets.bottom, alignment: .topLeading)
            .ignoresSafeArea()
        }
        .background(Theme.ground.ignoresSafeArea())
        .overlay { overlays }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.entrance, value: drawing)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.entrance, value: session.suggestion?.id)
        .animation(Theme.motion, value: session.showDebug)
        .onAppear(perform: readIsland)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in readIsland() }
    }

    // MARK: The column

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Text(session.currentStep.instruction)
                .font(Theme.cookTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
                .padding(.top, Theme.space8)
                .accessibilityAddTraits(.isHeader)
                .id(session.stepIndex)
                .transition(.opacity)
            Spacer(minLength: 0)
            bottomGroup
        }
        .animation(Theme.motion, value: session.stepIndex)
    }

    private var topRow: some View {
        HStack(spacing: Theme.space12) {
            Group {
                if let next = session.nextScheduledStep {
                    Text("Step \(session.stepIndex + 1) of \(session.recipe.steps.count) · next in \(Text(next.at, style: .timer))")
                } else {
                    Text("Step \(session.stepIndex + 1) of \(session.recipe.steps.count)")
                }
            }
            .font(Theme.cookCaption)
            .monospacedDigit()
            .foregroundStyle(Theme.slate)
            .lineLimit(1)
            .accessibilityLabel("\(session.recipe.title), step \(session.stepIndex + 1) of \(session.recipe.steps.count)")
            ProgressSegments(done: session.stepIndex + 1, total: session.recipe.steps.count)
                .frame(width: 120)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            RoundIconButton(systemImage: "questionmark", label: "What you can say", size: .small, style: .quiet) {
                session.noteTouch()
                session.open(.help)
            }
            RoundIconButton(systemImage: "xmark", label: "Leave the recipe", style: .quiet, action: close)
        }
        .frame(height: 44)
    }

    /// The timer card (or the button that starts this step's timer) and Back / Next step; the
    /// offer takes both places. A setup warning or the assistant's answer sits above.
    @ViewBuilder private var bottomGroup: some View {
        let notice = hasSetupNotice || session.answerText != nil
        VStack(alignment: .leading, spacing: notice ? Theme.space12 : Theme.space24) {
            if notice {
                VStack(alignment: .leading, spacing: 0) {
                    SetupCheckNotice(check: session.setupCheck)
                    if !hasSetupNotice, let answer = session.answerText {
                        Text(answer)
                            .font(Theme.cookCaption)
                            .foregroundStyle(Theme.slate)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
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
                .id(offer.id)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            } else {
                timerSlot
                buttons
            }
        }
        .animation(Theme.motion, value: notice)
    }

    private var hasSetupNotice: Bool {
        if case .done(let result) = session.setupCheck.stage, result.fix != nil { return true }
        return false
    }

    @ViewBuilder private var timerSlot: some View {
        Group {
            if let timer = featuredTimer(session.timers) {
                CookTimerCard(session: session, timer: timer) { showTimers = true }
            } else if session.canStartStepTimer,
                      let minutes = session.currentStep.watch?.timerMinutes ?? session.currentStep.timer?.minutes {
                // No timer yet on a timed step: start it by touch, as the old Timer button did.
                QuietButton(title: "Start the \(Recipe.timerLength(minutes: minutes)) timer", systemImage: "timer") {
                    session.noteTouch()
                    session.startStepTimer()
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
        .frame(height: 72)
    }

    private var buttons: some View {
        HStack(spacing: Theme.space12) {
            QuietButton(title: "Back", size: .cook) {
                session.noteTouch()
                session.previousStep()
            }
            .frame(width: 150)
            .disabled(session.stepIndex == 0)
            .opacity(session.stepIndex == 0 ? 0.4 : 1)
            .accessibilityLabel("Previous step")

            Button {
                session.noteTouch()
                session.nextStep()
            } label: {
                HStack(spacing: Theme.space12) {
                    Text("Next step").lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .font(Theme.cookBodyStrong)
                .frame(maxWidth: .infinity, minHeight: 68)
            }
            .buttonStyle(KitPressStyle(fill: Theme.beet, foreground: .white))
            .disabled(session.isLastStep)
            .opacity(session.isLastStep ? 0.4 : 1)
            .accessibilityLabel("Next step")
        }
        .frame(height: 68)
    }

    // MARK: Drawing

    private var drawingColumn: some View {
        VStack(alignment: .leading, spacing: Theme.space12) {
            Text(session.draftRegion == nil ? "Drag a box around the pot" : "Drag again to redraw it")
                .font(Theme.cookCaption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.space12)
            Spacer(minLength: 0)
            PrimaryButton(title: "Done", size: .cook) { session.confirmPan() }
                .disabled(session.draftRegion == nil)
                .opacity(session.draftRegion == nil ? 0.4 : 1)
                .accessibilityLabel("Done, watch this pot")
            QuietButton(title: "Skip the camera", size: .cook) { session.cancelMarking() }
        }
    }

    // MARK: Over the screen

    @ViewBuilder private var overlays: some View {
        ZStack {
            if session.showDebug && !drawing {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        RoundIconButton(systemImage: "xmark", label: "Hide details", size: .small, style: .card) {
                            session.showDebug = false
                        }
                        .padding(Theme.space8)
                        DebugPanel(session: session)
                    }
                    .frame(width: 340)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                    .floatingShadow()
                    .padding(.vertical, 12)
                    .padding(.trailing, 12)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
            if showTimers && session.timers.count > 1 {
                TimersSheet(session: session) { showTimers = false }
                    .transition(.opacity)
            }
            if confirmLeave {
                BottomSheet(title: "Leave the recipe?", close: { confirmLeave = false }) {
                    Text("Your timers keep running, and the recipe stays where you left it.")
                        .font(Theme.cookCaption)
                        .foregroundStyle(Theme.slate)
                    HStack(spacing: Theme.space12) {
                        QuietButton(title: "Keep cooking", size: .cook) { confirmLeave = false }
                        PrimaryButton(title: "Leave", size: .cook) {
                            confirmLeave = false
                            session.showRecipes()
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.motion, value: showTimers)
        .animation(Theme.motion, value: confirmLeave)
    }

    // MARK: Actions

    /// Back to Home; the cook stays resumable from the Cook tab. Asks first only while a timer runs.
    private func close() {
        session.noteTouch()
        if session.timers.contains(where: { !$0.isDone }) {
            confirmLeave = true
        } else {
            session.showRecipes()
        }
    }

    /// A tap on the camera box: drawing, with the last box already drawn if there is one.
    private func openDrawing() {
        guard session.cameraOn else { return }
        let offered = session.offeredPan
        session.markPan()
        if session.draftRegion == nil, let offered { session.draftRegion = offered }
    }

    private func readIsland() {
        switch UIDevice.current.orientation {
        // The phone's top, and its island, on the left.
        case .landscapeLeft: islandLeading = true
        case .landscapeRight: islandLeading = false
        default:
            let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
            if let orientation = scene?.effectiveGeometry.interfaceOrientation, orientation.isLandscape {
                islandLeading = orientation == .landscapeRight
            }
        }
    }
}

/// The camera box: radius 20, the card shadow, the live picture filling it (clipped), the
/// chip at 10, 10, and the setup check card along its bottom. Camera off, it shows the ground
/// with "Camera off" and Turn on. A tap opens drawing the pan box.
struct CookCameraBox: View {
    let session: CookSession
    let drawing: Bool
    let openDrawing: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        ZStack(alignment: .topLeading) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !drawing {
                CookChip(session: session, staged: staged)
                    .padding(10)
            }
            if session.cameraOn && staged == nil {
                CameraStatusOverlay(status: session.cameraStatus)
                SetupCheckView(check: session.setupCheck)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .clipShape(shape)
        .background(shape.fill(Theme.ground).cardShadow())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(drawing ? "Camera picture. Drag a box around the pot." : "Camera")
    }

    @ViewBuilder private var picture: some View {
        if let staged, staged.isEmpty == false {
            DishPhoto(recipe: session.recipe)
        } else if !session.cameraOn {
            VStack(spacing: Theme.space8) {
                Image(systemName: "video.slash")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.slate)
                    .accessibilityHidden(true)
                Text("Camera off")
                    .font(Theme.cookCaption)
                    .foregroundStyle(Theme.slate)
                QuietButton(title: "Turn on") {
                    session.noteTouch()
                    session.setCamera(on: true)
                }
                .frame(width: 140)
                .accessibilityLabel("Turn on the camera")
            }
        } else {
            CameraStage(session: session, fill: !drawing)
                .contentShape(Rectangle())
                // While drawing, only the stage's own drag gesture takes touches.
                .gesture(
                    TapGesture().onEnded {
                        session.noteTouch()
                        openDrawing()
                    },
                    including: drawing ? .subviews : .all
                )
                .accessibilityAddTraits(drawing ? AccessibilityTraits() : .isButton)
                .accessibilityHint(drawing ? "" : "Draws the box around the pot")
        }
    }

    /// The `-uiScreen` name in a screenshot build: the dish photo stands in for the camera.
    private var staged: String? {
        #if DEBUG
        return ScreenshotStage.requested
        #else
        return nil
        #endif
    }
}

#Preview(traits: .landscapeLeft) {
    CookScreen(session: CookSession())
}
