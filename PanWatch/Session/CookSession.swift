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
    /// Touches, voice commands and offers in this cook, for the Nov 4 gates.
    private(set) var stats = CookStats()
    let usage = UsageLog() // usage-log
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
    /// The assistant's reply, shown on the listening line while it is said.
    private(set) var answerText: String?
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
    /// One engine for speaking and listening, so the microphone can hear the cook over the app.
    private let audio = AudioIO()
    private let speaker: Speaker
    private let listener: VoiceListener
    private let alarms = CookAlarms()
    @ObservationIgnored private var started = false
    /// Starting and stopping the camera, one after another.
    @ObservationIgnored private var cameraWork: Task<Void, Never>?
    /// Said at launch when a saved cook is picked up again.
    @ObservationIgnored private var welcome: String?

    var currentStep: RecipeStep { recipe.steps[stepIndex] }
    var isLastStep: Bool { stepIndex == recipe.steps.count - 1 }

    init() {
        speaker = Speaker(audio: audio)
        listener = VoiceListener(audio: audio)
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
            speak: { [weak self] text in self?.speak(.answer, text) },
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
            self?.usage.listened(report) // usage-log
        }
        listener.isAppSpeaking = { [weak self] in
            self?.speaker.isSpeaking ?? false
        }
        listener.spokenText = { [weak self] in
            self?.speaker.currentText
        }
        // A "yes" or "okay" over the app's own question is the answer to it.
        listener.awaitingAnswer = { [weak self] in
            guard let self else { return false }
            return self.suggestion != nil || self.question != nil || self.isMarkingPan
                || (self.needsPan && self.offeredPan != nil)
        }
        // The cook started talking over a prompt: stop it. It isn't read again unless asked.
        listener.onBargeIn = { [weak self] in
            self?.cookSpokeAt = Date()
            self?.speaker.stop()
        }
        listener.intentContext = { [weak self] in
            self?.intentContext
        }
        listener.assistantContext = { [weak self] in
            self?.assistantContext
        }
        listener.onAssistant = { [weak self] reply, text in
            self?.assistantReplied(reply, heard: text)
        }
        listener.screen = { [weak self] in
            self?.screen ?? .cook
        }
        cameraOn = UserDefaults.standard.object(forKey: Self.cameraKey) as? Bool ?? true
        if cameraOn { offeredPan = savedPan() }
        let resumed = resumeCook(timers: restoreTimers())
        if resumed {
            welcome = "Welcome back. Step \(stepIndex + 1). \(currentStep.spokenText)"
                + (offeredPan != nil ? " \(Self.samePlacePrompt)" : "")
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        if let welcome {
            speak(.resume, welcome)
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
        openPanDrawingIfNeeded()
    }

    // MARK: Recipe steps

    func nextStep(by source: StepSource = .touch) {
        guard !isLastStep else { return }
        go(to: stepIndex + 1, by: source)
    }

    func previousStep(by source: StepSource = .touch) {
        guard stepIndex > 0 else { return }
        go(to: stepIndex - 1, by: source)
    }

    /// `saying` is a timer's "done" that calls this step out with it.
    private func go(to index: Int, by source: StepSource, saying text: String? = nil) {
        stepIndex = index
        usage.stepChanged(to: index, of: recipe.steps.count) // usage-log
        suggestion = nil
        refreshArming()
        saveCook()
        if let text {
            speak(.timerDone, text)
        } else {
            speak(.stepChanged(by: source), "Step \(index + 1). \(currentStep.spokenText)")
        }
    }

    // MARK: Recipes

    /// Starts `recipe` from its first step. Running timers keep going, but call-outs
    /// waiting on them belonged to the old recipe, so those are dropped.
    func choose(_ recipe: Recipe, by source: StepSource = .touch) {
        self.recipe = recipe
        usage.cookStarted(recipe.title) // usage-log
        cookUnderWay = true
        screen = .cook
        removeScheduled(scheduledSteps)
        finishedSteps = []
        suggestion = nil
        stats = CookStats()
        stepIndex = 0
        refreshArming()
        saveCook()
        speak(.recipeChosen(by: source), "\(recipe.title). Step 1. \(currentStep.spokenText)", short: "\(recipe.title). Step 1.")
        openPanDrawingIfNeeded()
    }

    /// Starts this recipe again from step 1: running timers and their alarms are cleared, and
    /// so are the step call-outs waiting on them. Said as "start over", or the Restart button.
    func restartRecipe(by source: StepSource = .touch) {
        for timer in timers { removeTimer(timer.id) }
        timers = []
        screen = .cook
        choose(recipe, by: source)
    }

    func showRecipes() {
        usage.offerGone() // usage-log
        screen = .recipes
        suggestion = nil
        refreshArming()
    }

    /// A tap on the cooking screen. Picking a recipe and marking the pan are setup and
    /// aren't counted.
    func noteTouch() {
        stats.noteTouch()
        usage.touched() // usage-log
    }

    // MARK: Marking the pan

    /// When a pan box is needed on the cook screen, go straight to drawing it, with the last
    /// saved box already drawn if there is one: the cook confirms it or draws a new one.
    func openPanDrawingIfNeeded() {
        guard needsPan, screen == .cook, !isChoosingRecipe else { return }
        let saved = offeredPan
        markPan()
        if let saved { draftRegion = saved }
    }

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
        speak(.guidance, offeredPan != nil ? Self.samePlacePrompt : "Draw a box around the pan.")
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
        usage.camera(on: on) // usage-log
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
                self.openPanDrawingIfNeeded()
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
        usage.offerMade() // usage-log
        refreshArming()
        // "Yes" or "start the timer" accepts, "no" dismisses; so do the volume buttons.
        speak(.offer, offerText(watch))
    }

    private func offerText(_ watch: AdditionWatch) -> String {
        "Looks like the \(watch.ingredient) went in. Start a \(watch.timerMinutes) minute timer?"
    }

    // MARK: Voice commands

    func toggleListening() {
        listeningResume?.cancel()
        listeningPausedUntil = nil
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
    /// On every screen, so a menu can be closed in the cook's own words.
    private var intentContext: IntentContext? {
        return IntentContext(
            step: currentStep.instruction,
            offer: suggestion.map { offerText($0.watch) },
            timers: timers.filter { !$0.isDone }.map {
                IntentContext.RunningTimer(label: $0.label, secondsLeft: Int($0.end.timeIntervalSinceNow.rounded()))
            }
        )
    }

    /// The recipe and where the cook is, for the assistant: small, rebuilt every turn.
    private var assistantContext: AssistantContext? {
        let next = stepIndex + 1 < recipe.steps.count ? recipe.steps[stepIndex + 1].instruction : nil
        return AssistantContext(
            recipe: recipe.title,
            stepNumber: stepIndex + 1,
            stepCount: recipe.steps.count,
            step: currentStep.instruction,
            nextStep: next,
            ingredients: recipe.ingredients,
            timers: intentContext?.timers ?? [],
            offer: suggestion.map { offerText($0.watch) },
            facts: recipe.steps.flatMap { [$0.instruction, $0.spokenText] }
                + recipe.steps.compactMap(\.watch).map { "\($0.timerMinutes) minutes" }
                + recipe.ingredients
        )
    }

    /// Acts on the assistant's reply. A tool's action is the command the cook could have
    /// said and goes through `handle`, so an offer still needs its yes; an answer is spoken
    /// through the policy's answer path and shown; a late reply only plays the
    /// "not understood" sound.
    private func assistantReplied(_ reply: CookAssistant.Reply, heard text: String) {
        switch reply.outcome {
        case .action(let action):
            if case .setTimer(let minutes, let name?) = action {
                usage.heard(.setTimer(minutes: minutes), text: text) // usage-log
                if screen != .recipes { stats.noteVoice() }
                showHeard(text)
                cookSpokeAt = Date()
                let label = name.prefix(1).uppercased() + name.dropFirst()
                startTimer(label: label, minutes: minutes)
                speak(.confirmation(visible: true), "\(label) timer set for \(Self.spoken(Double(minutes) * 60)).")
            } else if let command = action.command {
                handle(command, heard: text)
            }
        case .answer(let line):
            if screen != .recipes { stats.noteVoice() }
            showHeard(text)
            cookSpokeAt = Date()
            showAnswer(line)
            speak(.answer, line)
        case .timedOut, .failed:
            speak(.notUnderstood, "")
        case .silent:
            break
        }
    }

    /// With voice processing, the microphone doesn't hear the app, so listening goes on
    /// while it talks and the cook can cut it short. Without it, listening pauses.
    private func speakingChanged(_ speaking: Bool) {
        if speaking {
            if !speaker.cancelsEcho { listener.hold() }
        } else {
            sampleVoiceID = nil
            listener.appStoppedSpeaking()
            if listener.isHeld { listener.resume() }
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

    // MARK: Screens

    /// What fills the screen. Menus are opened by voice or a tap; "done" goes back to cook.
    private(set) var screen: AppScreen = .recipes
    /// True while the recipe menu is up: at launch, and when the cook asks for it.
    var isChoosingRecipe: Bool { screen == .recipes }
    /// A dish has been chosen (or a saved cook resumed), so the recipe menu can mark it.
    private(set) var cookUnderWay = false
    /// The screen the help overlay was opened from, whose commands it lists first.
    private(set) var helpFrom: AppScreen = .cook
    @ObservationIgnored private var helpClose: Task<Void, Never>?

    /// The three or four phrases that work right now, for the Say line.
    var sayPhrases: [String] {
        AppScreen.sayPhrases(
            screen: screen, drawing: isMarkingPan, offer: suggestion != nil, timerDone: timers.contains(where: \.isDone),
            needsPan: needsPan, canStartTimer: canStartStepTimer, cameraOn: cameraOn,
            voiceName: voiceOptions.first { $0.id == highlightedVoiceID }?.name ?? "Samantha"
        )
    }

    /// Opens a menu over the cook screen, or the cook screen itself. Help closes after 30 s.
    func open(_ next: AppScreen) {
        helpClose?.cancel()
        switch next {
        case .recipes:
            showRecipes()
            return
        case .voices:
            refreshVoices()
            if highlightedVoiceID == nil || !voiceOptions.contains(where: { $0.id == highlightedVoiceID }) {
                highlightedVoiceID = voiceID ?? voiceOptions.first?.id
            }
        case .help:
            if screen != .help { helpFrom = screen }
            helpClose = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.screen == .help else { return }
                self.closeMenu()
            }
        case .cook, .settings:
            break
        }
        screen = next
        refreshArming()
    }

    /// "Done", "close" or the Done button: back to the cook screen from any menu. Help
    /// goes back to the screen it was opened from, so it can be asked for from a menu.
    func closeMenu() {
        helpClose?.cancel()
        if screen == .voices { stopSample() }
        screen = screen == .help ? helpFrom : .cook
        refreshArming()
    }

    /// "What can I say" or its row in Settings: the help screen, reading the first four
    /// phrases that work where the cook asked.
    func showHelp() {
        open(.help)
        speak(.answer, "You can say " + helpPhrases.prefix(4).joined(separator: ", ") + ".")
    }

    /// The phrases that work on the screen help was opened from, which it shows first.
    var helpPhrases: [String] {
        AppScreen.sayPhrases(
            screen: helpFrom, drawing: isMarkingPan, offer: suggestion != nil, timerDone: timers.contains(where: \.isDone),
            needsPan: needsPan, canStartTimer: canStartStepTimer, cameraOn: cameraOn,
            voiceName: voiceOptions.first { $0.id == highlightedVoiceID }?.name ?? "Samantha"
        )
    }

    // MARK: Voices by voice

    /// The voices in the voice menu, best first; read when the menu opens.
    private(set) var voiceOptions: [VoiceOption] = []
    /// The row "next voice" and "use this one" point at.
    private(set) var highlightedVoiceID: String?

    /// Reads the phone's voices in the voice menu's order, so "next voice" walks down the
    /// rows as drawn: the cook's own, then the best (premium and enhanced), then the rest.
    func refreshVoices() {
        let all = Speaker.options()
        let natural = VoiceCatalog.menuOrder(blends: speaker.natural.allBlends).map(VoiceOption.init(natural:))
        let own = speaker.own.saved.map { [VoiceOption(own: $0)] } ?? []
        voiceOptions = natural + own + all.filter(\.isPersonal) + all.filter { !$0.isPersonal }
    }

    // MARK: The cook's own voice

    /// The recorded voice: what's saved and how its model is coming along.
    var ownVoice: OwnVoiceSource { speaker.own }

    /// A recorder on the shared engine, for the recording flow.
    func makeVoiceRecorder() -> VoiceRecorder {
        VoiceRecorder(audio: audio)
    }

    @ObservationIgnored private var heldForRecording = false

    /// Listening pauses while the cook reads the script, so it isn't taken as a command.
    func holdListeningForRecording(_ hold: Bool) {
        if hold, !listener.isHeld {
            listener.hold()
            heldForRecording = true
        } else if !hold, heldForRecording {
            heldForRecording = false
            if listener.isHeld { listener.resume() }
        }
    }

    /// Keeps a take from the recording flow as the cook's voice and starts making it.
    func keepOwnVoice(samples: [Float], name: String) throws {
        try speaker.own.keep(samples: samples, name: name)
        refreshVoices()
    }

    func renameOwnVoice(_ name: String) {
        speaker.own.rename(name)
        refreshVoices()
    }

    /// Removes the recording and the voice made from it; the voice picked before speaks.
    func deleteOwnVoice() {
        if OwnVoice.isOwn(voiceID) { chooseVoice(speaker.ownFallback) }
        speaker.own.delete()
        refreshVoices()
    }

    /// Starts the model download for the recorded voice, from the voice menu.
    func prepareOwnVoice() {
        speaker.own.prepare()
    }

    // MARK: Natural voices

    /// The Kokoro voices' download and load, for the voice menu.
    var naturalState: KokoroVoice.State { speaker.natural.state }

    /// Starts the natural voices' download, from the voice menu.
    func prepareNaturalVoices() {
        speaker.natural.prepare()
    }

    /// How fast every voice talks; nil until first read from `Speaker`.
    private var chosenSpeed: VoiceSpeed?
    var voiceSpeed: VoiceSpeed { chosenSpeed ?? speaker.speed }

    /// Sets the speed and says a line at it, so the cook hears the change.
    func setVoiceSpeed(_ speed: VoiceSpeed) {
        chosenSpeed = speed
        speaker.speed = speed
        sampleVoiceID = voiceID
        speaker.say("\(speed.title). Add the garlic and stir.")
    }

    /// "Make your own": mixes two voices and plays a line in the mix without saving it.
    func hearBlend(first: String, second: String, balance: Double) async throws {
        let id = try await speaker.natural.makeBlend(first: first, second: second, balance: balance, name: nil)
        playSample(voiceID: id)
    }

    /// Saves the mix under `name` and uses it from now on.
    func saveBlend(name: String, first: String, second: String, balance: Double) async throws {
        let id = try await speaker.natural.makeBlend(first: first, second: second, balance: balance, name: name)
        refreshVoices()
        if let option = voiceOptions.first(where: { $0.id == id }) { useVoice(option) }
    }

    func removeBlend(_ option: VoiceOption) {
        guard let pack = VoiceCatalog.pack(fromID: option.id) else { return }
        if voiceID == option.id { chooseVoice(nil) }
        speaker.natural.removeBlend(pack)
        refreshVoices()
    }

    /// "Use the British voice": the next natural voice of that kind after the one in use.
    private func useVoice(accent: VoiceAccent?, gender: VoiceGender?) {
        if voiceOptions.isEmpty { refreshVoices() }
        let list = VoiceCatalog.menuOrder(blends: speaker.natural.allBlends)
        let current = VoiceCatalog.isNatural(highlightedVoiceID) ? highlightedVoiceID : voiceID
        guard let next = VoiceCatalog.next(after: current, accent: accent, gender: gender, in: list),
              let option = voiceOptions.first(where: { $0.id == next.id })
        else {
            speak(.answer, "There's no voice like that.")
            return
        }
        useVoice(option)
    }

    /// A tap on a row in the voice menu.
    func highlightVoice(_ id: String) {
        highlightedVoiceID = id
    }

    /// "Next voice": the row below the highlighted one, played.
    func nextVoice() {
        if voiceOptions.isEmpty { refreshVoices() }
        guard !voiceOptions.isEmpty else { return }
        let index = voiceOptions.firstIndex { $0.id == highlightedVoiceID } ?? -1
        let next = voiceOptions[(index + 1) % voiceOptions.count]
        highlightedVoiceID = next.id
        playSample(voiceID: next.id)
    }

    /// "Use Samantha": chooses the voice and says hello in it.
    func useVoice(_ option: VoiceOption) {
        chooseVoice(option.id)
        highlightedVoiceID = option.id
        sampleVoiceID = option.id
        speaker.say(option.isOwn ? "This is your voice." : "Hi, I'm \(option.name).", voice: option.id)
    }

    /// The English voice called `name` (as heard, lowercased), the best of that name first.
    private func voice(named name: String) -> VoiceOption? {
        if voiceOptions.isEmpty { refreshVoices() }
        return voiceOptions.first { $0.name.lowercased() == name }
            ?? voiceOptions.first { $0.name.lowercased().hasPrefix(name) || name.hasPrefix($0.name.lowercased()) }
    }

    /// "Use my voice": the cook's recorded voice, then their Personal Voice, asking for
    /// that first if needed.
    private func useMyVoice() {
        if voiceOptions.isEmpty { refreshVoices() }
        let personal = Speaker.options().first(where: \.isPersonal)
        if let id = OwnVoice.mine(recorded: speaker.own.saved != nil, personalID: personal?.id),
           let mine = voiceOptions.first(where: { $0.id == id }) ?? personal {
            useVoice(mine)
            return
        }
        Task { [weak self] in
            _ = await Speaker.requestPersonalVoice()
            guard let self else { return }
            self.refreshVoices()
            if let mine = self.voiceOptions.first(where: \.isPersonal) {
                self.useVoice(mine)
            } else {
                self.speak(.answer, "There's no voice of yours yet. Record one in the voice menu.")
            }
        }
    }

    // MARK: Pausing the microphone

    /// When listening comes back by itself after "stop listening"; nil when not paused.
    private(set) var listeningPausedUntil: Date?
    @ObservationIgnored private var listeningResume: Task<Void, Never>?
    static let listeningPause: TimeInterval = 120

    /// "Stop listening": the microphone is off for 2 minutes, or until the Say line is tapped.
    func pauseListening() {
        listeningOn = false
        listeningPausedUntil = Date().addingTimeInterval(Self.listeningPause)
        refreshListening()
        listeningResume?.cancel()
        listeningResume = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.listeningPause))
            guard !Task.isCancelled, let self, !self.listeningOn else { return }
            self.listeningPausedUntil = nil
            self.listeningOn = true
            self.refreshListening()
            self.speak(.confirmation(visible: true), "Listening again.")
        }
    }

    // MARK: Handling commands

    /// A question waiting for a yes: only "start over" and cancelling a long timer ask.
    private enum Question {
        case startOver
        case cancelTimer(UUID)
    }
    @ObservationIgnored private var question: Question?

    /// Everything the buttons do, by voice, so the cook never has to touch the phone.
    private func handle(_ command: VoiceCommand, heard text: String) {
        usage.heard(command, text: text) // usage-log
        // Picking a recipe is setup and isn't counted.
        if screen != .recipes { stats.noteVoice() }
        showHeard(text)
        // The cook just spoke: for a moment, nothing but the answer to it.
        cookSpokeAt = Date()
        // Setup check: while it runs, "skip", "no" and "next" end it.
        if setupCheck.isRunning, [.skip, .no, .next].contains(command) { return setupCheck.skip() }
        let asked = question
        question = nil
        if let asked, command == .yes || command == .no {
            answer(asked, yes: command == .yes)
            return
        }
        // A menu covers the cook screen: "back" and "done" close it, and nothing moves behind it.
        if screen != .cook {
            switch command {
            case .back, .done:
                closeMenu()
                speak(.confirmation(visible: true), "Okay.")
                return
            case .next where screen == .voices:
                nextVoice()
                return
            case .next, .skip, .repeatStep, .goToStep, .startOver, .startTimer, .startWatching, .nudge, .mark:
                speak(.notUnderstood, "")
                return
            case .yes, .no:
                return
            default:
                break
            }
        }
        switch command {
        case .next, .skip:
            if isMarkingPan {
                if draftRegion != nil { confirmPanByVoice() }
            } else if isLastStep {
                speak(.answer, "That's the last step.")
            } else {
                nextStep(by: .voice)
            }
        case .back:
            if stepIndex == 0 {
                speak(.answer, "This is the first step.")
            } else {
                previousStep(by: .voice)
            }
        case .repeatStep:
            if let suggestion {
                speak(.answer, offerText(suggestion.watch))
            } else {
                speak(.answer, "Step \(stepIndex + 1). \(currentStep.spokenText)")
            }
        case .yes:
            if suggestion != nil {
                acceptSuggestion()
            } else if isMarkingPan, draftRegion != nil {
                confirmPanByVoice()
            } else if needsPan, offeredPan != nil {
                reuseLastPanByVoice()
            } else if timers.contains(where: \.isDone) {
                clearDoneTimers(byVoice: true)
            }
        case .no:
            if suggestion != nil {
                dismissSuggestion()
                speak(.confirmation(visible: true), "Okay.")
            } else if isMarkingPan {
                cancelMarking()
                speak(.confirmation(visible: true), "Okay.")
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
            guard cameraOn else {
                speak(.answer, "Turn on the camera first.")
                return
            }
            if screen != .cook { closeMenu() }
            markPan()
            // With no box to start from, one is drawn in the middle for the voice to move.
            if draftRegion == nil { draftRegion = .voiceStart }
            speak(.answer, "Is the box around the pan?")
        case .nudge(let nudge):
            guard isMarkingPan else { return speak(.notUnderstood, "") }
            draftRegion = (draftRegion ?? .voiceStart).nudged(nudge)
        case .ingredients:
            sayIngredients()
        case .cancelTimer:
            if let newest = timers.last(where: { !$0.isDone }) {
                cancelByVoice(newest)
            } else {
                speak(.answer, "No timers are running.")
            }
        case .cancelNamedTimer(let name):
            let named = timers.filter { VoiceCommand.timer(named: name, matches: $0.label) }
            if let timer = named.last(where: { !$0.isDone }) ?? named.last {
                cancelByVoice(timer)
            } else {
                speak(.answer, "There's no \(name) timer.")
            }
        case .setTimer(let minutes):
            startTimer(label: "\(minutes) minute", minutes: minutes)
            speak(.confirmation(visible: true), "Timer set for \(Self.spoken(Double(minutes) * 60)).")
        case .clearDone:
            if timers.contains(where: \.isDone) {
                clearDoneTimers(byVoice: true)
            } else {
                speak(.answer, "No timer is done.")
            }
        case .mark:
            // Practice: the cook marks each real add for the replay to score against.
            if camera.analyzer.recorder.mark() { speak(.confirmation(visible: true), "Marked.") } else { speak(.answer, "Practice recording is off.") }
        case .goToStep(let number):
            if number - 1 == stepIndex {
                speak(.answer, "Step \(number). \(currentStep.spokenText)")
            } else if recipe.steps.indices.contains(number - 1) {
                go(to: number - 1, by: .voice)
            } else {
                speak(.answer, "This recipe has \(recipe.steps.count) steps.")
            }
        case .whereAmI:
            speak(.answer, "\(recipe.title), step \(stepIndex + 1) of \(recipe.steps.count). \(currentStep.spokenText)")
        case .startOver:
            if stepIndex == 0 && timers.isEmpty {
                speak(.answer, "Step 1. \(currentStep.spokenText)")
            } else {
                question = .startOver
                speak(.answer, "Start the recipe over from step 1?")
            }
        case .showRecipes:
            open(.recipes)
            speak(.confirmation(visible: true), "What are you cooking?")
        case .makeRecipe(let title):
            guard let dish = Recipe.all.first(where: { $0.title == title }) else { return speak(.notUnderstood, "") }
            if dish.title == recipe.title && !isChoosingRecipe {
                speak(.answer, "Already cooking \(dish.title). Step \(stepIndex + 1).")
            } else if dish.title == recipe.title && stepIndex > 0 {
                // Back from the menu to the dish already under way, where it was.
                closeMenu()
                speak(.recipeChosen(by: .voice), "\(dish.title). Step \(stepIndex + 1). \(currentStep.spokenText)", short: "\(dish.title). Step \(stepIndex + 1).")
            } else {
                choose(dish, by: .voice)
            }
        case .camera(let on):
            if on == cameraOn {
                speak(.answer, on ? "The camera is on." : "The camera is off.")
            } else {
                setCamera(on: on)
                speak(.confirmation(visible: true), on ? "Camera on." : "Camera off.")
            }
        case .switchCamera(let toFront):
            guard cameraOn else {
                speak(.answer, "Turn on the camera first.")
                return
            }
            let front = toFront ?? (cameraPosition != .front)
            if front == (cameraPosition == .front) {
                speak(.answer, "Already using the \(front ? "front" : "back") camera.")
            } else {
                Task { [weak self] in await self?.flipCamera() }
                speak(.answer, front ? "Front camera. Draw a box around the pan." : "Back camera. Draw a box around the pan.")
            }
        case .showVoices:
            open(.voices)
            speak(.answer, "Say next voice to hear them.")
        case .tryVoice(let name):
            if screen != .voices { open(.voices) }
            if let name {
                if let option = voice(named: name) {
                    highlightedVoiceID = option.id
                    playSample(voiceID: option.id)
                } else {
                    speak(.answer, "There's no voice called \(name).")
                }
            } else if let id = highlightedVoiceID {
                playSample(voiceID: id)
            }
        case .nextVoice:
            if screen != .voices { open(.voices) }
            nextVoice()
        case .useVoice(let pick):
            switch pick {
            case .named(let name):
                if let option = voice(named: name) {
                    useVoice(option)
                } else {
                    speak(.answer, "There's no voice called \(name).")
                }
            case .highlighted:
                if let option = voiceOptions.first(where: { $0.id == highlightedVoiceID }) { useVoice(option) }
            case .mine:
                useMyVoice()
            case .kind(let accent, let gender):
                useVoice(accent: accent, gender: gender)
            }
        case .quiet:
            speaker.stop()
            voiceOn = false
        case .talk:
            voiceOn = true
            speak(.confirmation(visible: false), "Talking again.")
        case .stopListening:
            speak(.confirmation(visible: false), "Not listening for 2 minutes.")
            pauseListening()
        case .help:
            showHelp()
        case .settings:
            open(.settings)
            speak(.confirmation(visible: true), "Settings.")
        case .details(let show):
            showDebug = show ?? !showDebug
            if showDebug, screen != .cook { closeMenu() }
            speak(.confirmation(visible: true), showDebug ? "Details shown." : "Details hidden.")
        case .done:
            if isMarkingPan {
                cancelMarking()
                speak(.confirmation(visible: true), "Okay.")
            }
        case .recordPractice(let on):
            setPracticeRecording(on)
            speak(.answer, on ? "Recording practice. Say mark when something goes in." : "Practice recording stopped.")
        }
    }

    private func answer(_ asked: Question, yes: Bool) {
        guard yes else {
            speak(.confirmation(visible: true), "Okay.")
            return
        }
        switch asked {
        case .startOver:
            restartRecipe(by: .voice)
        case .cancelTimer(let id):
            guard let timer = timers.first(where: { $0.id == id }) else { return }
            removeTimer(id)
            speak(.confirmation(visible: true), "\(timer.label) timer cancelled.")
        }
    }

    /// A timer with more than a minute left is asked about first; a short one just goes.
    private func cancelByVoice(_ timer: CookTimer) {
        let left = timer.end.timeIntervalSinceNow
        if !timer.isDone && left > 60 {
            question = .cancelTimer(timer.id)
            speak(.answer, "Cancel the \(timer.label) timer, \(Self.spoken(left)) left?")
        } else {
            removeTimer(timer.id)
            speak(.confirmation(visible: true), "\(timer.label) timer cancelled.")
        }
    }

    /// "Clear it", "got it", the Clear button on a done row: done timers go.
    func clearDoneTimers(byVoice: Bool = false) {
        let done = timers.filter(\.isDone)
        for timer in done { removeTimer(timer.id) }
        if !done.isEmpty, byVoice { speak(.confirmation(visible: true), "Cleared.") }
    }

    private func sayIngredients() {
        let items = recipe.ingredients
        guard let last = items.last else {
            speak(.answer, "This recipe doesn't list its ingredients.")
            return
        }
        let list = items.count == 1 ? last : items.dropLast().joined(separator: ", ") + ", and " + last
        speak(.answer, "You'll need \(list).")
    }

    private func confirmPanByVoice() {
        confirmPan()
        if !setupCheck.isRunning { speak(.confirmation(visible: true), "Watching the pan.") } // Setup check: its prompt speaks instead
    }

    private func reuseLastPanByVoice() {
        reuseLastPan()
        if !setupCheck.isRunning { speak(.confirmation(visible: true), "Watching the pan.") } // Setup check: its prompt speaks instead
    }

    private func sayTimeLeft() {
        let running = timers.filter { !$0.isDone }
        guard !running.isEmpty else {
            speak(.answer, "No timers are running.")
            return
        }
        var text = running.map { "\($0.label), \(Self.spoken($0.end.timeIntervalSinceNow)) left." }.joined(separator: " ")
        if let next = nextScheduledStep {
            text += " Next step in \(Self.spoken(next.at.timeIntervalSinceNow))."
        }
        speak(.answer, text)
    }

    /// Shows the assistant's reply on the listening line for a few seconds.
    private func showAnswer(_ text: String) {
        answerText = text
        answerClear?.cancel()
        answerClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.answerText = nil
        }
    }
    @ObservationIgnored private var answerClear: Task<Void, Never>?

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
        usage.offerAnswered(accepted: true) // usage-log
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
            usage.likelyMiss(step: stepIndex, watching: cameraOn && region != nil) // usage-log
            ingredientWentIn(step: stepIndex, watch: watch)
        } else {
            speak(.answer, "There's no timer for this step.")
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
            speak(.confirmation(visible: true), "\(label) timer started. I'll tell you when it's time for the next step.")
        } else if index == stepIndex, !isLastStep {
            // The camera just confirmed this step happened, so the recipe moves on.
            stepIndex += 1
            usage.stepChanged(to: stepIndex, of: recipe.steps.count) // usage-log
            speak(.confirmation(visible: true), "\(label) timer started. Next, \(Self.lowercasingFirst(currentStep.spokenText))")
        } else {
            speak(.confirmation(visible: true), "\(label) timer started.")
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
            usage.callOut() // usage-log
            go(to: scheduled.stepIndex, by: .timerCallOut)
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
        usage.offerAnswered(accepted: false) // usage-log
        refreshArming()
    }

    /// Volume buttons and Camera Control: accept the offer if there is one, confirm the
    /// pan box while marking, otherwise go to the next step. Wet hands never have to
    /// touch the screen.
    func hardwareButtonPressed() {
        guard !isChoosingRecipe else { return }
        stats.noteButton()
        usage.button() // usage-log
        if suggestion != nil {
            acceptSuggestion()
        } else if isMarkingPan {
            if draftRegion != nil { confirmPan() }
        } else {
            nextStep(by: .button)
        }
    }

    func removeTimer(_ id: UUID) {
        usage.timerRemoved(timers.first { $0.id == id }) // usage-log
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
        usage.timerStarted(label, minutes: minutes) // usage-log
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
            usage.callOut() // usage-log
            go(to: step, by: .timerCallOut, saying: "\(label) timer is done. Step \(step + 1). \(recipe.steps[step].spokenText)")
        } else {
            speak(.timerDone, "\(label) timer is done.")
        }
    }

    /// When the cook last spoke to the app or cut it off: for a moment after, only the
    /// answer to what they said is spoken.
    @ObservationIgnored private var cookSpokeAt: Date?

    /// Every line the app might say goes through the speech policy, which decides between
    /// words, a short sound, or nothing.
    private func speak(_ moment: SpeechMoment, _ text: String, short: String? = nil) {
        let state = SpeechState(
            now: Date().timeIntervalSinceReferenceDate,
            interruptedAt: cookSpokeAt?.timeIntervalSinceReferenceDate,
            isSpeaking: speaker.isSpeaking
        )
        guard voiceOn else { return }
        switch SpeechPolicy.act(moment, text: text, short: short, state: state) {
        case .silent: return
        case .earcon(let earcon): speaker.say("", earcon: earcon)
        case .speak(let line): speaker.say(line)
        case .earconThenSpeak(let earcon, let line): speaker.say(line, earcon: earcon)
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
        cookUnderWay = true
        screen = .cook
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
