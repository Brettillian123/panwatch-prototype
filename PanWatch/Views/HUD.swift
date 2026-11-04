import AVFoundation
import Speech
import SwiftUI

// MARK: - Step panel

/// The step being done, top left, on one opaque Iron panel: where the cook is (18 pt,
/// near-phone detail), the step at 44 pt New York, and what the camera is doing in words.
struct StepCard: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow
            Text(session.currentStep.instruction)
                .font(Theme.step)
                .foregroundStyle(Theme.flour)
                .lineLimit(3)
                // 44 pt is the size. A step too long for three lines in this column scales
                // down rather than push the bar off the screen.
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            CameraLine(session: session)
                .padding(.top, Theme.tight)
        }
        .padding(.horizontal, Theme.gap)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.iron, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private var eyebrow: some View {
        HStack(spacing: Theme.tight) {
            Text("\(session.recipe.title) · step \(session.stepIndex + 1) of \(session.recipe.steps.count)")
            if let next = session.nextScheduledStep {
                Text("· next step in \(Text(next.at, style: .timer))")
                    .monospacedDigit()
                    .foregroundStyle(Theme.flour)
            }
        }
        .font(Theme.detail)
        .foregroundStyle(Theme.ash)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// What the camera is doing, in words, under the step. When the pan box is needed it
/// becomes the button that asks for one, and the recipe stays where it is.
struct CameraLine: View {
    let session: CookSession

    var body: some View {
        if session.needsPan {
            PanNeededLine(session: session)
        } else {
            let status = self.status
            Label {
                Text(status.text)
            } icon: {
                Image(systemName: status.symbol)
            }
            .font(Theme.control)
            .foregroundStyle(status.color)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: (symbol: String, text: String, color: Color) {
        guard let watch = session.currentStep.watch else {
            return session.cameraOn
                ? ("eye.slash", "Not needed this step", Theme.ash)
                : ("video.slash", "Camera off", Theme.ash)
        }
        if session.finishedSteps.contains(session.stepIndex) {
            return ("checkmark.circle.fill", "\(watch.ingredient.firstCapitalized) is in", Theme.herb)
        }
        if !session.cameraOn {
            return ("video.slash", "Camera off: say \u{201C}start the timer\u{201D} when it\u{2019}s in", Theme.ash)
        }
        if session.suggestion != nil {
            return ("timer", "Waiting for your answer", Theme.flour)
        }
        switch session.phase {
        case .watching:
            return ("eye", "Watching for the \(watch.ingredient)", Theme.herb)
        case .cooldown:
            return (PhaseStyle.symbol(for: .cooldown), PhaseStyle.label(for: .cooldown), Theme.herb)
        case .disarmed:
            return (PhaseStyle.symbol(for: .disarmed), PhaseStyle.label(for: .disarmed), Theme.ash)
        default:
            return (PhaseStyle.symbol(for: session.phase), PhaseStyle.label(for: session.phase), Theme.flour)
        }
    }
}

/// Pan needed: a filled Copper button where the camera line was. With a box saved from
/// last time, the cook can keep it without drawing.
struct PanNeededLine: View {
    let session: CookSession

    var body: some View {
        HStack(spacing: Theme.gap) {
            if session.offeredPan != nil {
                Button { session.reuseLastPan() } label: {
                    Label("Pan hasn\u{2019}t moved", systemImage: "checkmark")
                }
                .buttonStyle(WordButtonStyle(kind: .primary))
                Button("Draw again") { session.markPan() }
                    .buttonStyle(WordButtonStyle())
            } else {
                Button { session.markPan() } label: {
                    Label("Draw a box around the pan", systemImage: "viewfinder")
                }
                .buttonStyle(WordButtonStyle(kind: .primary))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Timers

/// Running and finished timers in the right column, newest on top. One timer gets the
/// 64 pt countdown under its label; from two, each row is label and 44 pt digits on one
/// line, because two 64 pt rows don't fit above the bar in landscape. No timers, nothing.
struct TimerStack: View {
    let session: CookSession

    var body: some View {
        let compact = session.timers.count > 1
        VStack(alignment: .trailing, spacing: Theme.gap) {
            ForEach(Array(session.timers.reversed())) { timer in
                TimerRow(timer: timer, compact: compact) {
                    session.noteTouch()
                    session.removeTimer(timer.id)
                }
            }
        }
    }
}

/// One timer: label, countdown and a worded Clear. Done, the digits become "Pasta is
/// done" in Chili with a Chili rule down the left edge; the panel stays Iron.
struct TimerRow: View {
    let timer: CookTimer
    let compact: Bool
    let clear: () -> Void

    var body: some View {
        HStack(spacing: Theme.tight) {
            Group {
                if compact {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.gap) {
                        if !timer.isDone { label }
                        countdown(font: Theme.compactDigits)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if !timer.isDone { label }
                        countdown(font: timer.isDone ? Theme.reading : Theme.digits)
                    }
                    .padding(.vertical, Theme.tight)
                }
            }
            .padding(.leading, Theme.gap)
            Spacer(minLength: 0)
            Button(action: clear) {
                Text("Clear")
                    .font(Theme.control)
                    .foregroundStyle(timer.isDone ? Theme.iron : Theme.flour)
                    .padding(.horizontal, 14)
                    .frame(minWidth: Theme.target, minHeight: Theme.target)
                    .background(timer.isDone ? Theme.primary : Theme.rule, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                    // The word is 44 tall; the touch area is 60 (C1), and 8 in from the
                    // panel edge keeps the corners concentric (20 - 8 = 12).
                    .padding(Theme.tight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear the \(timer.label) timer")
        }
        .background(Theme.iron, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(alignment: .leading) {
            if timer.isDone {
                Rectangle()
                    .fill(Theme.alert)
                    .frame(width: 4)
                    .padding(.vertical, Theme.panelRadius)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        Text(timer.label)
            .font(Theme.control)
            .foregroundStyle(Theme.flour)
            .lineLimit(1)
    }

    @ViewBuilder private func countdown(font: Font) -> some View {
        if timer.isDone {
            Text("\(timer.label) is done")
                .font(compact ? Theme.reading : font)
                .foregroundStyle(Theme.alert)
                .lineLimit(1)
        } else {
            Text(timerInterval: timer.start...timer.end, countsDown: true)
                .font(font)
                .foregroundStyle(Theme.flour)
                .lineLimit(1)
        }
    }
}

// MARK: - Bottom bar

/// Five word buttons, 64 pt tall and 16 apart: Back, Next step, Timer, Recipes, Settings.
/// Next step is the one primary action. Narrower (the details panel open), Recipes and
/// Settings, then Timer, move into More; words never turn into glyphs.
struct ControlBar: View {
    let session: CookSession
    let openSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(menuFrom: .nothing)
            bar(menuFrom: .recipes)
            bar(menuFrom: .timer)
        }
    }

    private enum MenuFrom { case nothing, recipes, timer }

    private func bar(menuFrom: MenuFrom) -> some View {
        HStack(spacing: Theme.gap) {
            Button { session.noteTouch(); session.previousStep() } label: {
                Text("Back").frame(maxWidth: .infinity)
            }
            .buttonStyle(WordButtonStyle(height: Theme.barHeight))
            .disabled(session.stepIndex == 0)
            .accessibilityLabel("Previous step")

            Button { session.noteTouch(); session.nextStep() } label: {
                Text("Next step").frame(maxWidth: .infinity)
            }
            .buttonStyle(WordButtonStyle(kind: .primary, height: Theme.barHeight))
            .disabled(session.isLastStep)

            if menuFrom != .timer {
                Button("Timer", action: startTimer)
                    .buttonStyle(WordButtonStyle(height: Theme.barHeight))
                    .disabled(!canTime)
                    .accessibilityLabel("Start this step's timer")
            }

            if menuFrom == .nothing {
                Button("Recipes") { session.showRecipes() }
                    .buttonStyle(WordButtonStyle(height: Theme.barHeight))
                Button("Settings", action: openSettings)
                    .buttonStyle(WordButtonStyle(height: Theme.barHeight))
            } else {
                Menu {
                    if menuFrom == .timer {
                        Button("Start the timer", action: startTimer).disabled(!canTime)
                    }
                    Button("Recipes") { session.showRecipes() }
                    Button("Settings", action: openSettings)
                } label: {
                    Text("More")
                }
                .menuStyle(.button)
                .buttonStyle(WordButtonStyle(height: Theme.barHeight))
            }
        }
    }

    /// "Timer" starts this step's timer, or accepts the offer when one is up.
    private var canTime: Bool { session.suggestion != nil || session.canStartStepTimer }

    private func startTimer() {
        session.noteTouch()
        session.startStepTimer()
    }
}

// MARK: - Say line

/// Along the bottom of every state: whether the app is listening, what it just heard, and
/// one phrase that works right now at 44 pt, changing every 4 s. Tapping it turns
/// listening off or on.
struct SayLine: View {
    let session: CookSession

    var body: some View {
        Group {
            if session.listeningOn && !session.micReady && micDenied {
                // Denied: the line says so in Chili and offers the way to fix it.
                HStack(spacing: Theme.gap) {
                    level(Theme.alert)
                    Text("Microphone off")
                        .font(Theme.control)
                        .foregroundStyle(Theme.alert)
                    Spacer(minLength: 0)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                }
                .padding(.trailing, Theme.tight)
            } else {
                Button {
                    session.noteTouch()
                    session.toggleListening()
                } label: {
                    HStack(spacing: Theme.gap) {
                        content
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(session.listeningOn ? "Stops listening" : "Starts listening")
            }
        }
        .padding(.leading, Theme.gap)
        .frame(maxWidth: .infinity, minHeight: Theme.bigTarget, maxHeight: Theme.bigTarget)
        .background(Theme.iron, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        if !session.listeningOn {
            level(Theme.ash)
            Text("Not listening · tap to listen")
                .font(Theme.control)
                .foregroundStyle(Theme.ash)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if !session.micReady {
            level(Theme.ash)
            Text("Starting the microphone")
                .font(Theme.control)
                .foregroundStyle(Theme.ash)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if let heard = session.heardText {
            level(Theme.copper)
            Text("Heard \u{201C}\(heard)\u{201D}")
                .font(Theme.reading)
                .foregroundStyle(Theme.copper)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            // No microphone level is published yet, so the bar is a steady Copper mark
            // for "listening" rather than a pulse that would pretend to be one.
            level(Theme.copper)
            Text("Listening")
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
            let phrases = self.phrases
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 4)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 4) % phrases.count
                Text("Say \u{201C}\(phrases[index])\u{201D}")
                    .font(Theme.reading)
                    .foregroundStyle(Theme.flour)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func level(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous)
            .fill(color)
            .frame(width: 4, height: 36)
            .accessibilityHidden(true)
    }

    /// Phrases that work right now, in the order they're most useful. Only commands the
    /// grammar understands today; never empty.
    private var phrases: [String] {
        if session.suggestion != nil { return ["yes", "not now"] }
        if session.isMarkingPan {
            return session.draftRegion == nil ? ["cancel"] : ["start watching", "cancel"]
        }
        var list: [String] = []
        if session.needsPan {
            list += session.offeredPan != nil ? ["yes", "draw the pan again"] : ["mark the pan"]
        }
        if !session.isLastStep { list.append("next step") }
        if session.canStartStepTimer { list.append("start the timer") }
        if session.timers.contains(where: { !$0.isDone }) { list.append("how long") }
        if session.stepIndex > 0 { list.append("back") }
        list += ["repeat", "ingredients"]
        if session.cameraOn && !session.needsPan { list.append("draw the pan again") }
        return list
    }

    private var micDenied: Bool {
        let speech = SFSpeechRecognizer.authorizationStatus()
        return AVAudioApplication.shared.recordPermission == .denied || speech == .denied || speech == .restricted
    }
}

// MARK: - Drawing the pan box

/// The one strip while drawing, top left over a screen cleared to the picture. It takes no
/// touches, so the box can be drawn right under it.
struct DrawingStrip: View {
    let session: CookSession

    var body: some View {
        let drawn = session.draftRegion != nil
        VStack(alignment: .leading, spacing: 4) {
            Text(drawn ? "Keep the phone still" : "Draw a box around the pan")
                .font(Theme.control)
                .foregroundStyle(Theme.flour)
            Text(drawn ? "Drag again to redraw it" : "Tap the pan or drag a box")
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
        }
        .ironPanel()
        .allowsHitTesting(false)
    }
}

/// Cancel and Start watching, the only buttons while drawing. Start watching waits for a box.
struct DrawPanBar: View {
    let session: CookSession

    var body: some View {
        HStack(spacing: Theme.gap) {
            Button("Cancel") { session.cancelMarking() }
                .buttonStyle(WordButtonStyle(height: Theme.barHeight))
            Button { session.confirmPan() } label: {
                Label("Start watching", systemImage: "eye")
            }
            .buttonStyle(WordButtonStyle(kind: .primary, height: Theme.barHeight))
            .disabled(session.draftRegion == nil)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Camera status

/// Starting, denied and failed, each drawn: the picture's place is never just black.
struct CameraStatusOverlay: View {
    let status: CameraStatus

    var body: some View {
        switch status {
        case .running:
            EmptyView()
        case .starting:
            HStack(spacing: Theme.gap) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.flour)
                Text("Starting the camera")
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
            }
            .ironPanel()
        case .denied:
            message(
                symbol: "video.slash",
                title: "Camera not allowed",
                detail: "Sous Vision watches the pan on this phone. Video is never saved or sent.",
                showsSettings: true
            )
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle", title: "The camera couldn\u{2019}t start", detail: reason, showsSettings: false)
        }
    }

    private func message(symbol: String, title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Label(title, systemImage: symbol)
                .font(Theme.control)
                .foregroundStyle(Theme.alert)
            Text(detail)
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
                .fixedSize(horizontal: false, vertical: true)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(WordButtonStyle(kind: .primary))
                .padding(.top, Theme.tight)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .ironPanel(padding: 24)
    }
}

// MARK: - Settings, for now

/// The old icon row as worded rows: stands in for the Settings screen `ui-menus` builds,
/// and goes when that lands. Each row says what it is, how it is now, and what a tap does.
struct InterimSettings: View {
    let session: CookSession
    let close: () -> Void
    @State private var choosingVoice = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text("Settings")
                .font(Theme.reading)
                .foregroundStyle(Theme.flour)
            ScrollView {
                VStack(spacing: 0) {
                    row("Camera", now: session.cameraOn ? "On" : "Off", action: session.cameraOn ? "Turn off" : "Turn on") {
                        session.setCamera(on: !session.cameraOn)
                    }
                    if session.cameraOn {
                        let front = session.cameraPosition == .front
                        row("Camera side", now: front ? "Front" : "Back", action: front ? "Use back" : "Use front") {
                            Task { await session.flipCamera() }
                        }
                        row("Pan box", now: session.region == nil ? "None" : "Drawn", say: "draw the pan again", action: "Draw again") {
                            close()
                            session.markPan()
                        }
                    }
                    row("Speaks", now: session.voiceOn ? "On" : "Quiet", action: session.voiceOn ? "Go quiet" : "Speak") {
                        session.voiceOn.toggle()
                    }
                    row("Voice", now: nil, action: "Choose") { choosingVoice = true }
                    row("Listening", now: session.listeningOn ? "On" : "Off", action: session.listeningOn ? "Stop" : "Listen") {
                        session.toggleListening()
                    }
                    row("Details", now: session.showDebug ? "Shown" : "Hidden", action: session.showDebug ? "Hide" : "Show") {
                        session.showDebug.toggle()
                        close()
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: close)
                    .buttonStyle(WordButtonStyle(kind: .primary))
            }
        }
        .padding(.top, Theme.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.iron)
        .sheet(isPresented: $choosingVoice) {
            VoicePicker(session: session)
        }
    }

    private func row(_ name: String, now: String?, say phrase: String? = nil, action word: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.gap) {
                Text(name)
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
                if let now {
                    Text(now)
                        .font(Theme.control)
                        .foregroundStyle(Theme.ash)
                }
                Spacer(minLength: Theme.gap)
                if let phrase {
                    Text("Say \u{201C}\(phrase)\u{201D}")
                        .font(Theme.detail)
                        .foregroundStyle(Theme.ash)
                }
                Button(word) {
                    session.noteTouch()
                    perform()
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
                .accessibilityLabel("\(name): \(word)")
            }
            .frame(minHeight: Theme.bigTarget)
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 1)
        }
    }
}

private extension String {
    /// "pasta" to "Pasta", leaving the rest alone.
    var firstCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
