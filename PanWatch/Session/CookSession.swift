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

    var showDebug = false
    var voiceOn = true
    /// Timers count seconds instead of minutes, for rehearsing the demo.
    var fastTimers = false
    /// Detector tuning. Views change it directly; call `applySettings()` afterwards.
    var settings: DetectorSettings

    let camera = CameraController()
    private let speaker = Speaker()
    @ObservationIgnored private var started = false

    var currentStep: RecipeStep { recipe.steps[stepIndex] }
    var isLastStep: Bool { stepIndex == recipe.steps.count - 1 }

    init() {
        settings = Self.loadSettings()
        camera.analyzer.update(settings: settings)
        camera.analyzer.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.receive(snapshot) }
        }
        camera.analyzer.onDecision = { [weak self] decision in
            Task { @MainActor in self?.receive(decision) }
        }
        camera.onRotationChanged = { [weak self] in
            Task { @MainActor in self?.phoneTurned() }
        }
    }

    func start() async {
        guard !started else { return }
        started = true
        cameraStatus = await camera.start(position: cameraPosition)
        refreshArming()
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

    private func go(to index: Int) {
        stepIndex = index
        suggestion = nil
        refreshArming()
        say("Step \(index + 1). \(currentStep.instruction)")
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
        camera.analyzer.setArmed(armed)
    }

    func applySettings() {
        camera.analyzer.update(settings: settings)
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
        say("Looks like the \(watch.ingredient) went in. Start a \(watch.timerMinutes) minute timer?")
    }

    // MARK: Suggestions and timers

    func acceptSuggestion() {
        guard let offer = suggestion else { return }
        suggestion = nil
        startTimer(label: offer.watch.timerLabel, minutes: offer.watch.timerMinutes)
        if offer.stepIndex == stepIndex, !isLastStep {
            // The camera just confirmed this step happened, so the recipe moves on.
            stepIndex += 1
            say("\(offer.watch.timerLabel) timer started. Next, \(Self.lowercasingFirst(currentStep.instruction))")
        } else {
            say("\(offer.watch.timerLabel) timer started.")
        }
        refreshArming()
    }

    func dismissSuggestion() {
        guard suggestion != nil else { return }
        suggestion = nil
        refreshArming()
    }

    /// Volume buttons and Camera Control: accept the offer if there is one, otherwise
    /// go to the next step. Wet hands never have to touch the screen.
    func hardwareButtonPressed() {
        if suggestion != nil {
            acceptSuggestion()
        } else if !isMarkingPan {
            nextStep()
        }
    }

    func removeTimer(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    private func startTimer(label: String, minutes: Int) {
        let seconds = Double(minutes) * (fastTimers ? 1 : 60)
        let now = Date()
        let timer = CookTimer(label: label, start: now, end: now.addingTimeInterval(seconds))
        timers.append(timer)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.finishTimer(timer.id)
        }
    }

    private func finishTimer(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isDone else { return }
        timers[index].isDone = true
        say("\(timers[index].label) timer is done.")
    }

    private func say(_ text: String) {
        if voiceOn { speaker.say(text) }
    }

    private static func lowercasingFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }

    // MARK: Saved tuning

    private static let settingsKey = "detectorSettings.v1"

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
