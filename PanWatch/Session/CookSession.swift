import AVFoundation
import Observation
import SwiftUI

/// A timer the cook accepted.
struct CookTimer: Identifiable, Sendable {
    /// Also the id of the timer's system alarm.
    var id = UUID()
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
    private(set) var recipe = Recipe.garlicButterPasta
    /// True while the recipe menu is up: at launch, and when the cook asks for it.
    private(set) var isChoosingRecipe = true
    /// Touches, voice commands and offers in this cook, for the Nov 4 gates.
    private(set) var stats = CookStats()
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

    /// The camera is in use. Off, there's no pan box and nothing is watched; the recipe,
    /// timers and voice work as before. A setting, saved.
    private(set) var cameraOn = true
    /// The pan box the camera watches, once confirmed.
    private(set) var region: NormRect?
    /// True while the cook is drawing the pan box, with the screen cleared to the picture.
    private(set) var isMarkingPan = false
    /// The box being drawn, before it's confirmed.
    var draftRegion: NormRect?
    /// The last confirmed box, offered again after a relaunch, a phone turn or the camera
    /// coming back on, until the cook says yes or draws a new one.
    private(set) var offeredPan: NormRect?
    /// The camera has no pan box. The cook screen asks for one without hiding anything.
    var needsPan: Bool { cameraOn && region == nil && !isMarkingPan }

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
    /// What listening is doing and what it last heard, for the debug panel.
    private(set) var voiceReport = VoiceReport()
    /// The voice picked in the voice menu, or nil for the best one installed.
    private(set) var voiceID: String?
    /// The voice whose sample is playing in the voice menu.
    private(set) var sampleVoiceID: String?
    /// Timers count seconds instead of minutes, for rehearsing the demo.
    var fastTimers = false
    /// Detector tuning. Views change it directly; call `applySettings()` afterwards.
    var settings: DetectorSettings

    let camera = CameraController()
    /// Setup check: measures this kitchen after the pan box is confirmed and tunes the detector to it.
    let setupCheck = SetupCheck()
    private let speaker = Speaker()
    private let listener = VoiceListener()
    private let alarms = CookAlarms()
    @ObservationIgnored private var started = false
    /// Starting and stopping the camera, one after another.
    @ObservationIgnored private var cameraWork: Task<Void, Never>?
    /// Said at launch when a saved cook is picked up again.
    @ObservationIgnored private var welcome: String?

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
        // Setup check.
        setupCheck.connect(
            camera: camera,
            settings: { [weak self] in self?.settings ?? DetectorSettings() },
            speak: { [weak self] text in self?.say(text) },
            retune: { [weak self] in self?.refreshArming() }
        )
        camera.onRotationChanged = { [weak self] in
            Task { @MainActor in self?.phoneTurned() }
        }
        speaker.onSpeakingChanged = { [weak self] speaking in
            self?.speakingChanged(speaking)
        }
        voiceID = speaker.voiceIdentifier
        listener.onReport = { [weak self] report in
            self?.voiceReport = report
        }
        listener.isAppSpeaking = { [weak self] in
            self?.speaker.isSpeaking ?? false
        }
        listener.intentContext = { [weak self] in
            self?.intentContext
        }
        cameraOn = UserDefaults.standard.object(forKey: Self.cameraKey) as? Bool ?? true
        if cameraOn { offeredPan = savedPan() }
        let resumed = resumeCook(timers: restoreTimers())
        if resumed {
            welcome = "Welcome back. Step \(stepIndex + 1). \(currentStep.instruction)"
                + (offeredPan != nil ? " \(Self.samePlacePrompt)" : "")
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        if let welcome {
            say(welcome)
            self.welcome = nil
        }
        if cameraOn {
            cameraStatus = await camera.start(position: cameraPosition)
        }
        refreshArming()
        // Ask for the microphone at launch, so the prompt never appears mid-cook.
        micReady = await listener.requestPermission()
        refreshListening()
        // Timers that ring with the app closed need their own permission; ask now too.
        await alarms.requestPermission()
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
        saveCook()
        say(text ?? "Step \(index + 1). \(currentStep.instruction)")
    }

    // MARK: Recipes

    /// Starts `recipe` from its first step. Running timers keep going, but call-outs
    /// waiting on them belonged to the old recipe, so those are dropped.
    func choose(_ recipe: Recipe) {
        self.recipe = recipe
        isChoosingRecipe = false
        removeScheduled(scheduledSteps)
        finishedSteps = []
        suggestion = nil
        stats = CookStats()
        stepIndex = 0
        refreshArming()
        saveCook()
        say("\(recipe.title). Step 1. \(currentStep.instruction)")
    }

    func showRecipes() {
        isChoosingRecipe = true
        suggestion = nil
        refreshArming()
    }

    /// A tap on the cooking screen. Picking a recipe and marking the pan are setup and
    /// aren't counted.
    func noteTouch() {
        stats.noteTouch()
    }

    // MARK: Marking the pan

    /// Clears the screen to the camera picture for drawing the pan box. The button, or
    /// "draw a new box" said at any time, comes here.
    func markPan() {
        guard cameraOn else { return }
        isMarkingPan = true
        draftRegion = region
        // Let exposure adapt while the cook sets up; it locks again on confirm.
        camera.setAdjustmentsLocked(false)
        refreshArming()
    }

    func confirmPan() {
        guard let draft = draftRegion else { return }
        let box = draft.atLeast(0.08)
        region = box
        draftRegion = nil
        offeredPan = nil
        isMarkingPan = false
        camera.analyzer.setRegion(box)
        camera.setAdjustmentsLocked(true)
        refreshArming()
        savePan(box)
        setupCheck.panConfirmed(box) // Setup check
    }

    /// "Yes" to the last box: watches it again without drawing.
    func reuseLastPan() {
        guard cameraOn, region == nil, let box = offeredPan else { return }
        draftRegion = box
        confirmPan()
    }

    /// Back to the cook screen. With no box yet, the recipe goes on unwatched and the
    /// screen keeps asking for one.
    func cancelMarking() {
        isMarkingPan = false
        draftRegion = nil
        if region != nil { camera.setAdjustmentsLocked(true) }
        refreshArming()
    }

    func flipCamera() async {
        guard cameraOn else { return }
        cameraPosition = cameraPosition == .front ? .back : .front
        forgetPan()
        cameraStatus = await camera.start(position: cameraPosition)
    }

    private func phoneTurned() {
        guard cameraOn, region != nil else { return }
        forgetPan()
        // Turned back to where it was, the last box still fits; the cook says if it does.
        say(offeredPan != nil ? Self.samePlacePrompt : "Draw a box around the pan.")
    }

    /// Drops the box and goes back to asking for one, offering the last box drawn on this
    /// camera. Never forces the cook into drawing.
    private func forgetPan() {
        region = nil
        camera.analyzer.setRegion(nil)
        isMarkingPan = false
        draftRegion = nil
        offeredPan = savedPan()
        camera.setAdjustmentsLocked(false)
        refreshArming()
    }

    static let samePlacePrompt = "Is the pot in the same place? Say yes if the phone hasn't moved, or draw it again."

    // MARK: Camera on or off

    /// Turns the camera on or off, and saves the choice. Off, the camera stops and nothing
    /// is watched. On, it starts again and asks for the pan box, offering the last one.
    func setCamera(on: Bool) {
        guard on != cameraOn else { return }
        cameraOn = on
        UserDefaults.standard.set(on, forKey: Self.cameraKey)
        if on {
            cameraStatus = .starting
            offeredPan = savedPan()
        } else {
            suggestion = nil
            isMarkingPan = false
            draftRegion = nil
            offeredPan = nil
            region = nil
            camera.analyzer.setRegion(nil)
        }
        refreshArming()
        // Each switch waits for the one before, then does whatever the setting is by then.
        let previous = cameraWork
        cameraWork = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            if self.cameraOn {
                self.cameraStatus = await self.camera.start(position: self.cameraPosition)
            } else {
                await self.camera.stop()
            }
        }
    }

    private static let cameraKey = "cameraOn.v1"
    private static let panKey = "lastPan.v1"

    /// The last confirmed box, saved with the camera it was drawn on.
    private func savePan(_ box: NormRect) {
        let saved = SavedPan(box: box, backCamera: cameraPosition == .back)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.panKey)
    }

    /// The last confirmed box, if it was drawn on the camera in use now.
    private func savedPan() -> NormRect? {
        guard let data = UserDefaults.standard.data(forKey: Self.panKey),
              let saved = try? JSONDecoder().decode(SavedPan.self, from: data),
              saved.backCamera == (cameraPosition == .back) else { return nil }
        return saved.box
    }

    // MARK: Detection

    /// Whether the camera should be judging right now.
    private func refreshArming() {
        let armed = cameraOn && region != nil && !isMarkingPan && !isChoosingRecipe && suggestion == nil && currentStep.watch != nil
            && !finishedSteps.contains(stepIndex) && !setupCheck.isRunning // Setup check: never judge the hand it asks for
        camera.analyzer.update(settings: effectiveSettings)
        camera.analyzer.setArmed(armed)
        camera.analyzer.recorder.setStep(stepIndex, watch: currentStep.watch)
    }

    /// The tuning in force for the current step (see `DetectorSettings.applying`).
    private var effectiveSettings: DetectorSettings {
        setupCheck.tuned(settings).applying(currentStep.watch) // Setup check: this box's tuning
    }

    func applySettings() {
        camera.analyzer.update(settings: effectiveSettings)
        camera.analyzer.recorder.setTuning(settings)
        Self.save(settings)
    }

    /// Starts or stops the practice recording, from the debug panel.
    func setPracticeRecording(_ on: Bool) {
        let recorder = camera.analyzer.recorder
        guard on else { return recorder.stop() }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        try? recorder.start(notes: "\(recipe.title), step \(stepIndex + 1), build \(version)", settings: settings)
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
        stats.noteOffer()
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

    /// What the screen shows, for the on-device model that reads what the keywords miss.
    /// Nil while the recipe menu is up, where nothing is done by voice.
    private var intentContext: IntentContext? {
        guard !isChoosingRecipe else { return nil }
        return IntentContext(
            step: currentStep.instruction,
            offer: suggestion.map { offerText($0.watch) },
            timers: timers.filter { !$0.isDone }.map {
                IntentContext.RunningTimer(label: $0.label, secondsLeft: Int($0.end.timeIntervalSinceNow.rounded()))
            }
        )
    }

    private func speakingChanged(_ speaking: Bool) {
        if speaking {
            listener.hold()
        } else {
            sampleVoiceID = nil
            listener.resume()
        }
    }

    // MARK: Voice menu

    /// Saves the voice for every prompt from now on; nil goes back to the best installed.
    func chooseVoice(_ id: String?) {
        voiceID = id
        speaker.voiceIdentifier = id
    }

    /// Plays a line in `id`'s voice, even with the voice muted, since the cook asked for it.
    /// Listening pauses for it like any other prompt.
    func playSample(voiceID id: String) {
        sampleVoiceID = id
        speaker.say("Step two. Add the garlic and stir until it smells toasty.", voice: id)
    }

    func stopSample() {
        sampleVoiceID = nil
        speaker.stop()
    }

    /// Everything the buttons do, by voice, so the cook never has to touch the phone.
    private func handle(_ command: VoiceCommand, heard text: String) {
        // The recipe menu is picked by touch; nothing should change behind it.
        guard !isChoosingRecipe else { return }
        stats.noteVoice()
        showHeard(text)
        // Setup check: while it runs, "skip", "no" and "next" end it.
        if setupCheck.isRunning, [.skip, .no, .next].contains(command) { return setupCheck.skip() }
        switch command {
        case .next, .skip:
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
            } else if needsPan, offeredPan != nil {
                reuseLastPanByVoice()
            }
        case .no:
            if suggestion != nil {
                dismissSuggestion()
                say("Okay.")
            } else if isMarkingPan {
                cancelMarking()
                say("Okay.")
            }
        case .startTimer:
            startStepTimer()
        case .checkSetup: // Setup check
            setupCheck.checkAgain(possible: region != nil && !isMarkingPan)
        case .timeLeft:
            sayTimeLeft()
        case .startWatching:
            if isMarkingPan, draftRegion != nil {
                confirmPanByVoice()
            } else if needsPan, offeredPan != nil {
                reuseLastPanByVoice()
            }
        case .drawPan:
            if cameraOn {
                markPan()
                say("Draw a box around the pan.")
            } else {
                say("Turn on the camera first.")
            }
        case .ingredients:
            sayIngredients()
        case .cancelTimer:
            if let newest = timers.last(where: { !$0.isDone }) {
                removeTimer(newest.id)
                say("\(newest.label) timer cancelled.")
            } else {
                say("No timers are running.")
            }
        case .mark:
            // Practice: the cook marks each real add for the replay to score against.
            say(camera.analyzer.recorder.mark() ? "Marked." : "Practice recording is off.")
        }
    }

    private func sayIngredients() {
        let items = recipe.ingredients
        guard let last = items.last else {
            say("This recipe doesn't list its ingredients.")
            return
        }
        let list = items.count == 1 ? last : items.dropLast().joined(separator: ", ") + ", and " + last
        say("You'll need \(list).")
    }

    private func confirmPanByVoice() {
        confirmPan()
        if !setupCheck.isRunning { say("Watching the pan.") } // Setup check: its prompt speaks instead
    }

    private func reuseLastPanByVoice() {
        reuseLastPan()
        if !setupCheck.isRunning { say("Watching the pan.") } // Setup check: its prompt speaks instead
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
        stats.noteAccepted()
        ingredientWentIn(step: offer.stepIndex, watch: offer.watch)
    }

    /// This step still has a timer to start: something goes in, and it hasn't yet.
    var canStartStepTimer: Bool {
        currentStep.watch != nil && !finishedSteps.contains(stepIndex)
    }

    /// "Start the timer": accepts the offer, or starts the step's timer when the camera
    /// missed it, the cook was quicker, or the camera is off.
    func startStepTimer() {
        if suggestion != nil {
            acceptSuggestion()
        } else if let watch = currentStep.watch, canStartStepTimer {
            ingredientWentIn(step: stepIndex, watch: watch)
        } else {
            say("There's no timer for this step.")
        }
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
        saveCook()
    }

    /// Steps cued to this timer are called out when it has that much time left, so the
    /// parts of the dish finish together. Removing the timer cancels them.
    private func scheduleSteps(for timer: CookTimer) {
        let saved = SavedTimer(id: timer.id, label: timer.label, start: timer.start, end: timer.end)
        for callOut in StepCallOuts.cued(to: saved, in: recipe, after: stepIndex) {
            schedule(callOut)
        }
    }

    private func schedule(_ callOut: StepCallOut) {
        // A cue longer than the timer is called out right away.
        let at = callOut.atTimerEnd ? callOut.at : max(Date(), callOut.at)
        let scheduled = ScheduledStep(stepIndex: callOut.stepIndex, timerID: callOut.timerID, at: at, atTimerEnd: callOut.atTimerEnd)
        scheduledSteps.append(scheduled)
        scheduledSteps.sort { $0.at < $1.at }
        guard !callOut.atTimerEnd else { return }
        let id = scheduled.id
        let delay = max(0, at.timeIntervalSinceNow)
        cueTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.cueArrived(id)
        }
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
        stats.noteDismissed()
        refreshArming()
    }

    /// Volume buttons and Camera Control: accept the offer if there is one, confirm the
    /// pan box while marking, otherwise go to the next step. Wet hands never have to
    /// touch the screen.
    func hardwareButtonPressed() {
        guard !isChoosingRecipe else { return }
        stats.noteButton()
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
        alarms.cancel(id: id)
        saveTimers()
    }

    @discardableResult
    private func startTimer(label: String, minutes: Int) -> CookTimer {
        let seconds = Double(minutes) * (fastTimers ? 1 : 60)
        let now = Date()
        let timer = CookTimer(label: label, start: now, end: now.addingTimeInterval(seconds))
        timers.append(timer)
        scheduleFinish(timer)
        // The system alarm rings even with the app closed or the phone locked.
        alarms.schedule(id: timer.id, label: label, at: timer.end)
        saveTimers()
        return timer
    }

    /// The in-app "done" call-out, which also announces any step waiting on the timer.
    private func scheduleFinish(_ timer: CookTimer) {
        let delay = max(0, timer.end.timeIntervalSinceNow)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.finishTimer(timer.id)
        }
    }

    private func finishTimer(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isDone else { return }
        timers[index].isDone = true
        saveTimers()
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

    // MARK: Saved timers

    private static let timersKey = "runningTimers.v1"

    /// Running timers are saved so they come back if the app is closed and reopened. iOS
    /// keeps their alarms, so only the screen and the in-app call-out need restoring.
    private func saveTimers() {
        let running = timers.filter { !$0.isDone }.map {
            SavedTimer(id: $0.id, label: $0.label, start: $0.start, end: $0.end)
        }
        UserDefaults.standard.set(SavedTimers.encode(running), forKey: Self.timersKey)
    }

    /// Brings back the running timers, and returns every saved one, finished while the app
    /// was closed or not, so the step call-outs can be lined up again.
    private func restoreTimers() -> [SavedTimer] {
        guard let data = UserDefaults.standard.data(forKey: Self.timersKey) else { return [] }
        let all = SavedTimers.decode(data)
        for saved in SavedTimers.stillRunning(all, at: Date()) {
            let timer = CookTimer(id: saved.id, label: saved.label, start: saved.start, end: saved.end)
            timers.append(timer)
            scheduleFinish(timer)
        }
        saveTimers()
        return all
    }

    // MARK: Saved cook

    private static let cookKey = "cook.v1"

    /// The recipe, the step and what already went in, saved whenever they change.
    private func saveCook() {
        let cook = SavedCook(recipeTitle: recipe.title, stepIndex: stepIndex, finishedSteps: finishedSteps, savedAt: Date())
        UserDefaults.standard.set(cook.encoded(), forKey: Self.cookKey)
    }

    /// Picks up a cook saved in the last 6 hours: skips the menu, goes back to its step,
    /// and lines up the step call-outs again from the saved timers. A step whose moment
    /// passed while the app was closed is where the cook resumes.
    private func resumeCook(timers saved: [SavedTimer]) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.cookKey),
              let cook = SavedCook.decode(data),
              let recipe = cook.recipe(in: Recipe.all, at: Date()) else { return false }
        self.recipe = recipe
        stepIndex = cook.stepIndex
        finishedSteps = cook.finishedSteps
        isChoosingRecipe = false
        let resumed = StepCallOuts.resumed(from: saved, in: recipe, at: stepIndex, now: Date())
        if let step = resumed.catchUp {
            stepIndex = step
            saveCook()
        }
        for callOut in resumed.upcoming {
            schedule(callOut)
        }
        return true
    }

    // MARK: Saved tuning

    // v5: holding-hand and visible-change settings added, so tuning saved by older builds is ignored.
    private static let settingsKey = "detectorSettings.v5"

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

/// The last confirmed pan box, kept across launches. A box only fits the camera it was
/// drawn on.
private struct SavedPan: Codable {
    let box: NormRect
    let backCamera: Bool
}
