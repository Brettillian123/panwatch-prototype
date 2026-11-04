import SwiftUI

/// The current recipe step, big enough to read from across the stove.
struct StepCard: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(session.recipe.title.uppercased())  ·  STEP \(session.stepIndex + 1) OF \(session.recipe.steps.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(session.currentStep.instruction)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            WatchStatusChip(session: session)
            if let next = session.nextScheduledStep {
                (Text("Next step in ") + Text(next.at, style: .timer).monospacedDigit())
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            VoiceHint(session: session)
        }
        .padding(18)
        .frame(maxWidth: 470, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Says whether the camera is watching this step, and what it's doing.
struct WatchStatusChip: View {
    let session: CookSession

    var body: some View {
        let status = self.status
        // Title size, not subheadline: this is the line a cook reads from a meter away.
        Label(status.text, systemImage: status.symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(status.color.opacity(0.18), in: Capsule())
    }

    private var status: (symbol: String, text: String, color: Color) {
        guard let watch = session.currentStep.watch else {
            return ("eye.slash", "Camera not needed for this step", .gray)
        }
        if session.finishedSteps.contains(session.stepIndex) {
            return ("checkmark.circle.fill", "The \(watch.ingredient) is in", .green)
        }
        if session.isMarkingPan || session.region == nil {
            return ("viewfinder", "Mark the pan to start watching", .orange)
        }
        if session.suggestion != nil {
            return ("timer", "Waiting for your answer", .cyan)
        }
        if session.phase == .watching {
            return ("eye", "Watching for the \(watch.ingredient)", .green)
        }
        return (PhaseStyle.symbol(for: session.phase), PhaseStyle.label(for: session.phase), PhaseStyle.color(for: session.phase))
    }
}

/// What the cook can say, or what was just heard.
struct VoiceHint: View {
    let session: CookSession

    var body: some View {
        if session.micReady && session.listeningOn {
            Group {
                if let heard = session.heardText {
                    Label("Heard \u{201C}\(heard)\u{201D}", systemImage: "checkmark.bubble.fill")
                        .foregroundStyle(.cyan)
                } else {
                    Label("Say \u{201C}next\u{201D}, \u{201C}back\u{201D}, \u{201C}repeat\u{201D} or \u{201C}start the timer\u{201D}", systemImage: "mic.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}

/// Running and finished timers, top right.
struct TimerStack: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(session.timers) { timer in
                HStack(spacing: 10) {
                    Image(systemName: timer.isDone ? "bell.fill" : "timer")
                        .font(.title3)
                    Text(timer.label)
                        .font(.headline)
                    Group {
                        if timer.isDone {
                            Text("Done")
                        } else {
                            Text(timerInterval: timer.start...timer.end, countsDown: true)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    Button {
                        session.noteTouch()
                        session.removeTimer(timer.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    // Button labels take the tint, not the inherited white, so set it here
                    // or the mark comes out accent-blue on the red "done" capsule.
                    .tint(.white)
                    .accessibilityLabel("Remove \(timer.label) timer")
                }
                .foregroundStyle(.white)
                .padding(.leading, 16)
                .padding(.vertical, 2)
                .padding(.trailing, 2)
                .background(timer.isDone ? Color.red : Color.black.opacity(0.72), in: Capsule())
            }
        }
    }
}

/// Step navigation and setup controls along the bottom. While the pan is being marked,
/// the step buttons give way to Cancel and Start watching, so nothing has to sit over
/// the pan.
struct ControlBar: View {
    let session: CookSession

    var body: some View {
        // With the debug panel open there isn't room for the titles, so the buttons
        // fall back to their icons. VoiceOver still reads the titles.
        ViewThatFits(in: .horizontal) {
            buttons
            buttons.labelStyle(.iconOnly)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if session.isMarkingPan {
                if session.region != nil {
                    Button { session.cancelMarking() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                Button { session.confirmPan() } label: {
                    Label("Start watching", systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(session.draftRegion == nil)
            } else {
                Button { session.noteTouch(); session.previousStep() } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(session.stepIndex == 0)

                Button { session.noteTouch(); session.nextStep() } label: {
                    Label("Next step", systemImage: "chevron.right")
                }
                .disabled(session.isLastStep)

                Button { session.noteTouch(); session.markPan() } label: {
                    Label("Mark pan", systemImage: "viewfinder")
                }

                Button { session.showRecipes() } label: {
                    Label("Recipes", systemImage: "list.bullet")
                }
            }

            Spacer(minLength: 8)

            Button { session.noteTouch(); session.toggleListening() } label: {
                Image(systemName: session.listeningOn ? "mic.fill" : "mic.slash.fill")
            }
            .accessibilityLabel(session.listeningOn ? "Stop listening for commands" : "Listen for commands")

            Button { session.noteTouch(); session.voiceOn.toggle() } label: {
                Image(systemName: session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(session.voiceOn ? "Mute voice" : "Unmute voice")

            Button { session.noteTouch(); Task { await session.flipCamera() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
            }
            .accessibilityLabel("Switch camera")

            Button { session.showDebug.toggle() } label: {
                Image(systemName: "waveform.path.ecg")
            }
            .accessibilityLabel(session.showDebug ? "Hide detection details" : "Show detection details")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .padding(10)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

/// Instructions while the cook draws the pan box. Kept small and in the top-left corner
/// so the pan, which sits in the middle of the picture, stays visible and touchable.
/// The Cancel and Start watching buttons live in the control bar at the bottom.
struct MarkPanBanner: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.draftRegion == nil ? "Draw a box around the pan" : "Box drawn. Start watching?")
                .font(.title2.weight(.bold))
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var hint: String {
        if let reason = session.markingReason { return reason }
        if session.draftRegion == nil {
            return "Tap the pan for a quick box, or drag to draw one."
        }
        return "Drag again to redraw it. Keep the phone still from now on: exposure and white balance lock when watching starts."
    }
}

/// Covers the screen when the camera can't run.
struct CameraStatusOverlay: View {
    let status: CameraStatus

    var body: some View {
        switch status {
        case .running:
            EmptyView()
        case .starting:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        case .denied:
            message(
                symbol: "camera.fill",
                title: "Sous Vision needs the camera to watch your pan",
                detail: "Video is analyzed on this phone and never saved or sent anywhere.",
                showsSettings: true
            )
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle.fill", title: "The camera couldn't start", detail: reason, showsSettings: false)
        }
    }

    private func message(symbol: String, title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 520)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
