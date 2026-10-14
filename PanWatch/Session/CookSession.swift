import AVFoundation
import Observation
import SwiftUI

/// A timer the cook accepted.
struct CookTimer: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let start: Date
    let end: Date
    var isDone = false
}

/// The app's offer after the camera saw something go in.
struct TimerSuggestion: Identifiable {
    let id = UUID()
    let stepIndex: Int
    let watch: AdditionWatch
    let decision: DetectorDecision
    let before: CGImage?
    let after: CGImage?
}

/// A recipe step that will be called out once a running timer reaches its cue.
struct ScheduledStep: Identifiable, Sendable {
    let id = UUID()
    let stepIndex: Int
    let timerID: UUID
    let at: Date
    /// Called out together with the timer's own "done", not by a separate task.
    let atTimerEnd: Bool
}

/// Pictures of the most recent decision, for the debug panel.
struct DecisionPictures {
    let before: CGImage?
    let after: CGImage?
    let changes: CGImage?
}

/// Everything the screen shows, plus the recipe state machine that decides when the
/// camera should care. Detection only runs during steps that add something, which is
/// what keeps stirring and walking past from ever being judged.
@MainActor
@Observable
final class CookSession {
    let recipe = Recipe.garlicButterPasta
    private(set) var stepIndex = 0

    private(set) var cameraStatus: CameraStatus = .starting
    private(set) var cameraPosition: AVCaptureDevice.Position = .front
    /// Size of the analyzed frames, which is also what the preview shows.
    private(set) var frameSize = CGSize.zero
    /// Latest analyzer state, about 15 times a second.
    private(set) var live = AnalyzerSnapshot()
    /// Same as `live.phase`, but only changes when the phase does, so views that only
    /// need the phase don't redraw 15 times a second.
    private(set) var phase: AdditionDetector.Phase = .disarmed

    /// The pan box the camera watches, once confirmed.
    private(set) var region: NormRect?
    /// True while the cook is drawing the pan box.
    private(set) var isMarkingPan = true
    /// The box being drawn, before it's confirmed.
    var draftRegion: NormRect?
    /// Why the cook is being asked to mark the pan again, if it isn't the first time.
    private(set) var markingReason: String?

    private(set) var suggestion: TimerSuggestion?
    private(set) var timers: [CookTimer] = []
    /// Newest first.
    private(set) var decisions: [DetectorDecision] = []
    private(set) var lastPictures: DecisionPictures?
    /// Watched steps whose ingredient already went in, so the camera stops judging them.
    private(set) var finishedSteps: Set<Int> = []
    /// Steps waiting to be called out at the right moment, earliest first.
    private(set) var scheduledSteps: [ScheduledStep] = []
    /// The next step the recipe will call out on its own, if one is waiting.
    var nextScheduledStep: ScheduledStep? { scheduledSteps.first { $0.stepIndex > stepIndex } }
    @ObservationIgnored private var cueTasks: [UUID: Task<Void, Never>] = [:]

    var showDebug = false
    var voiceOn = true
    /// Spoken commands are on. The microphone button turns them off, say while presenting.
    private(set) var listeningOn = true
    /// Microphone and speech recognition are allowed.
    private(set) var micReady = false
    /// What was last heard as a command, shown for a moment so the cook knows it landed.
    private(set) var heardText: String?
    @ObservationIgnored private var heardClear: Task<Void, Never>?
    /// Timers count seconds instead of minutes, for rehearsing the demo.
    var fastTimers = false
    /// Detector tuning. Views change it directly; call `applySettings()` afterwards.
    var settings: DetectorSettings

    let camera = CameraController()
    private let speaker = Speaker()
    private let listener = VoiceListener()
    @ObservationIgnored private var started = false

    var currentStep: RecipeStep { recipe.steps[stepIndex] }
    var isLastStep: Bool { stepIndex == recipe.steps.count - 1 }

    init() {
        settings = Self.loadSettings()
        camera.analyzer.update(settings: effectiveSettings)
        camera.analyzer.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.receive(snapshot) }
        }
        camera.analyzer.onDecision = { [weak self] decision in
            Task { @MainActor in self?.receive(decision) }
        }
        camera.onRotationChanged = { [weak self] in
            Task { @MainActor in self?.phoneTurned() }
        }
        speaker.onSpeakingChanged = { [weak self] speaking in
            self?.speakingChanged(speaking)
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        cameraStatus = await camera.start(position: cameraPosition)
        refreshArming()
        // Ask for the microphone at launch, so the prompt never appears mid-cook.
        micReady = await listener.requestPermission()
        refreshListening()
    }

    // MARK: Recipe steps

    func nextStep() {
        guard !isLastStep else { return }
        go(to: stepIndex + 1)
    }

    func previousStep() {
        guard stepIndex > 0 else { return }
        go(to: stepIndex - 1)
    }

    private func go(to index: Int, saying text: String? = nil) {
        stepIndex = index
        suggestion = nil
        refreshArming()
        say(text ?? "Step \(index + 1). \(currentStep.instruction)")
    }

    // MARK: Marking the pan

    func markPan() {
        isMarkingPan = true
        draftRegion = region
        markingReason = nil
        // Let exposure adapt while the cook sets up; it locks again on confirm.
        camera.setAdjustmentsLocked(false)
        refreshArming()
    }

    func confirmPan() {
        guard let draft = draftRegion else { return }
        let box = draft.atLeast(0.08)
        region = box
        draftRegion = nil
        isMarkingPan = false
        markingReason = nil
        camera.analyzer.setRegion(box)
        camera.setAdjustmentsLocked(true)
        refreshArming()
    }

    func cancelMarking() {
        guard region != nil else { return }
        isMarkingPan = false
        draftRegion = nil
        markingReason = nil
        camera.setAdjustmentsLocked(true)
        refreshArming()
    }

    func flipCamera() async {
        cameraPosition = cameraPosition == .front ? .back : .front
        forgetPan()
        cameraStatus = await camera.start(position: cameraPosition)
    }

    private func phoneTurned() {
        guard region != nil else { return }
        forgetPan()
        markingReason = "The phone turned, so the pan moved on screen. Mark it again."
    }

    private func forgetPan() {
        region = nil
        camera.analyzer.setRegion(nil)
        markPan()
        draftRegion = nil
    }

    // MARK: Detection

    /// Whether the camera should be judging right now.
    private func refreshArming() {
        let armed = region != nil && !isMarkingPan && suggestion == nil && currentStep.watch != nil
            && !finishedSteps.contains(stepIndex)
        camera.analyzer.update(settings: effectiveSettings)
        camera.analyzer.setArmed(armed)
    }

    /// The tuning in force for the current step. Some ingredients, like minced garlic,
    /// change only a little of the pan, so their step asks for less change.
    private var effectiveSettings: DetectorSettings {
        var effective = settings
        if let minimum = currentStep.watch?.minimumChange {
            effective.additionThreshold = min(effective.additionThreshold, minimum)
        }
        // Only ingredients carried in the hand count a hand letting go.
        effective.countRelease = settings.countRelease && currentStep.watch?.countsRelease == true
        return effective
    }

    func applySettings() {
        camera.analyzer.update(settings: effectiveSettings)
        Self.save(settings)
    }

    func resetSettings() {
        settings = DetectorSettings()
        applySettings()
    }

    private func receive(_ snapshot: AnalyzerSnapshot) {
        live = snapshot
        if snapshot.phase != phase { phase = snapshot.phase }
        let size = CGSize(width: snapshot.frameWidth, height: snapshot.frameHeight)
        if size != frameSize { frameSize = size }
    }

    private func receive(_ decision: DetectorDecision) {
        decisions.insert(decision, at: 0)
        if decisions.count > 30 { decisions.removeLast(decisions.count - 30) }
        let changes = decision.after.changedMask(from: decision.before, rule: settings.changeRule)
        let pictures = DecisionPictures(
            before: decision.before.cgImage(),
            after: decision.after.cgImage(),
            changes: decision.after.cgImage(highlight: changes)
        )
        lastPictures = pictures

        guard decision.outcome == .addition, suggestion == nil, let watch = currentStep.watch else { return }
        suggestion = TimerSuggestion(
            stepIndex: stepIndex,
            watch: watch,
            decision: decision,
            before: pictures.before,
            after: pictures.after
        )
        refreshArming()
        // "Yes" or "start the timer" accepts, "no" dismisses; so do the volume buttons.
        say(offerText(watch))
    }

    private func offerText(_ watch: AdditionWatch) -> String {
        "Looks like the \(watch.ingredient) went in. Start a \(watch.timerMinutes) minute timer?"
    }

    // MARK: Voice commands

    func toggleListening() {
        listeningOn.toggle()
        refreshListening()
    }

    private func refreshListening() {
        if listeningOn && micReady {
            listener.start { [weak self] command, text in
                self?.handle(command, heard: text)
            }
        } else {
            listener.stop()
        }
    }

    private func speakingChanged(_ speaking: Bool) {
        if speaking {
            listener.hold()
        } else {
            listener.resume()
        }
    }

    /// Everything the buttons do, by voice, so the cook never has to touch the phone.
    private func handle(_ command: VoiceCommand, heard text: String) {
        showHeard(text)
        switch command {
        case .next:
            if isMarkingPan {
                if draftRegion != nil { confirmPanByVoice() }
            } else if isLastStep {
                say("That's the last step.")
            } else {
                nextStep()
            }
        case .back:
            if stepIndex == 0 {
                say("This is the first step.")
            } else {
                previousStep()
            }
        case .repeatStep:
            if let suggestion {
                say(offerText(suggestion.watch))
            } else {
                say("Step \(stepIndex + 1). \(currentStep.instruction)")
            }
        case .yes:
            if suggestion != nil {
                acceptSuggestion()
            } else if isMarkingPan, draftRegion != nil {
                confirmPanByVoice()
            }
        case .no:
            if suggestion != nil {
                dismissSuggestion()
                say("Okay.")
            }
        case .startTimer:
            if suggestion != nil {
                acceptSuggestion()
            } else if let watch = currentStep.watch, !finishedSteps.contains(stepIndex) {
                // The camera missed it, or the cook was quicker: start the step's timer anyway.
                ingredientWentIn(step: stepIndex, watch: watch)
            } else {
                say("There's no timer for this step.")
            }
        case .timeLeft:
            sayTimeLeft()
        case .startWatching:
            if isMarkingPan, draftRegion != nil { confirmPanByVoice() }
        }
    }

    private func confirmPanByVoice() {
        confirmPan()
        say("Watching the pan.")
    }

    private func sayTimeLeft() {
        let running = timers.filter { !$0.isDone }
        guard !running.isEmpty else {
            say("No timers are running.")
            return
        }
        var text = running.map { "\($0.label), \(Self.spoken($0.end.timeIntervalSinceNow)) left." }.joined(separator: " ")
        if let next = nextScheduledStep {
            text += " Next step in \(Self.spoken(next.at.timeIntervalSinceNow))."
        }
        say(text)
    }

    private func showHeard(_ text: String) {
        heardText = text
        heardClear?.cancel()
        heardClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.heardText = nil
        }
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let rest = total % 60
        func unit(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        if minutes == 0 { return unit(rest, "second") }
        if rest == 0 { return unit(minutes, "minute") }
        return "\(unit(minutes, "minute")) \(unit(rest, "second"))"
    }

    // MARK: Suggestions and timers

    func acceptSuggestion() {
        guard let offer = suggestion else { return }
        suggestion = nil
        ingredientWentIn(step: offer.stepIndex, watch: offer.watch)
    }

    /// Starts the ingredient's timer, lines up the steps that wait on it, and says what's next.
    private func ingredientWentIn(step index: Int, watch: AdditionWatch) {
        finishedSteps.insert(index)
        let label = watch.timerLabel
        let timer = startTimer(label: label, minutes: watch.timerMinutes)
        scheduleSteps(for: timer)
        let nextIsTimed = scheduledSteps.contains { $0.stepIndex == stepIndex + 1 }
        if index == stepIndex, !isLastStep, nextIsTimed {
            // The next step depends on this timer, so the recipe waits and calls it out.
            say("\(label) timer started. I'll tell you when it's time for the next step.")
        } else if index == stepIndex, !isLastStep {
            // The camera just confirmed this step happened, so the recipe moves on.
            stepIndex += 1
            say("\(label) timer started. Next, \(Self.lowercasingFirst(currentStep.instruction))")
        } else {
            say("\(label) timer started.")
        }
        refreshArming()
    }

    /// Steps cued to this timer are called out when it has that much time left, so the
    /// parts of the dish finish together. Removing the timer cancels them.
    private func scheduleSteps(for timer: CookTimer) {
        let scale = fastTimers ? 1.0 / 60 : 1.0
        for (index, step) in recipe.steps.enumerated() where index > stepIndex {
            guard let cue = step.cue, cue.timerLabel == timer.label else { continue }
            let atEnd = cue.secondsLeft <= 0
            let at = atEnd ? timer.end : max(Date(), timer.end.addingTimeInterval(-Double(cue.secondsLeft) * scale))
            let scheduled = ScheduledStep(stepIndex: index, timerID: timer.id, at: at, atTimerEnd: atEnd)
            scheduledSteps.append(scheduled)
            guard !atEnd else { continue }
            let id = scheduled.id
            let delay = max(0, at.timeIntervalSinceNow)
            cueTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.cueArrived(id)
            }
        }
        scheduledSteps.sort { $0.at < $1.at }
    }

    private func cueArrived(_ id: UUID) {
        guard let scheduled = scheduledSteps.first(where: { $0.id == id }) else { return }
        removeScheduled([scheduled])
        if scheduled.stepIndex > stepIndex {
            go(to: scheduled.stepIndex)
        }
    }

    private func removeScheduled(_ items: [ScheduledStep]) {
        let ids = Set(items.map(\.id))
        for id in ids {
            cueTasks.removeValue(forKey: id)?.cancel()
        }
        scheduledSteps.removeAll { ids.contains($0.id) }
    }

    func dismissSuggestion() {
        guard suggestion != nil else { return }
        suggestion = nil
        refreshArming()
    }

    /// Volume buttons and Camera Control: accept the offer if there is one, confirm the
    /// pan box while marking, otherwise go to the next step. Wet hands never have to
    /// touch the screen.
    func hardwareButtonPressed() {
        if suggestion != nil {
            acceptSuggestion()
        } else if isMarkingPan {
            if draftRegion != nil { confirmPan() }
        } else {
            nextStep()
        }
    }

    func removeTimer(_ id: UUID) {
        timers.removeAll { $0.id == id }
        removeScheduled(scheduledSteps.filter { $0.timerID == id })
    }

    @discardableResult
    private func startTimer(label: String, minutes: Int) -> CookTimer {
        let seconds = Double(minutes) * (fastTimers ? 1 : 60)
        let now = Date()
        let timer = CookTimer(label: label, start: now, end: now.addingTimeInterval(seconds))
        timers.append(timer)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.finishTimer(timer.id)
        }
        return timer
    }

    private func finishTimer(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isDone else { return }
        timers[index].isDone = true
        let label = timers[index].label
        // A step cued for the end of this timer is called out together with it.
        let atEnd = scheduledSteps.filter { $0.timerID == id && $0.atTimerEnd }
        removeScheduled(atEnd)
        if let step = atEnd.map(\.stepIndex).max(), step > stepIndex {
            go(to: step, saying: "\(label) timer is done. Step \(step + 1). \(recipe.steps[step].instruction)")
        } else {
            say("\(label) timer is done.")
        }
    }

    private func say(_ text: String, then: (() -> Void)? = nil) {
        if voiceOn {
            speaker.say(text, then: then)
        } else {
            then?()
        }
    }

    private static func lowercasingFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    // MARK: Saved tuning

    // v3: the defaults changed, so tuning saved by older builds is ignored.
    private static let settingsKey = "detectorSettings.v3"

    private static func loadSettings() -> DetectorSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let saved = try? JSONDecoder().decode(DetectorSettings.self, from: data) else {
            return DetectorSettings()
        }
        return saved
    }

    private static func save(_ settings: DetectorSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
}
