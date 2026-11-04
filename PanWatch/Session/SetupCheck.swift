import Foundation
import Observation

/// The setup check: right after the pan box is confirmed the first time in a launch, and
/// whenever the cook says "check the setup". About seven seconds, spoken and on screen:
/// hands away while it measures the picture, then one hand over the pot while it measures
/// the hand, then "Ready" or the one fix to make. It sets the detector for this kitchen
/// (`SetupCalibration`) and keeps that tuning for the box. "Skip" or the button ends it.
@MainActor
@Observable
final class SetupCheck {
    enum Stage: Equatable {
        case idle
        /// "Keep your hands away for two seconds."
        case still
        /// "Now hold one hand over the pot."
        case hand
        case done(SetupCalibration.Result)
    }

    private(set) var stage: Stage = .idle
    /// When the running check started, for its progress bar.
    private(set) var startedAt = Date()
    /// The tuning for the confirmed box, from a check or saved from an earlier one.
    private(set) var tuning: SetupTuning?

    var isRunning: Bool { stage == .still || stage == .hand }

    // Timing, in seconds from the start. The first second of each step lets the cook move
    // before anything is measured: their hand just tapped the phone, then has to reach the pot.
    static let stillFrom = 1.0
    static let handAt = 3.0
    static let handFrom = 4.0
    static let finishAt = 7.0
    /// How long the result stays up.
    static let resultShown = 4.0

    @ObservationIgnored private weak var camera: CameraController?
    @ObservationIgnored private var settings: () -> DetectorSettings = { DetectorSettings() }
    @ObservationIgnored private var speak: (String) -> Void = { _ in }
    @ObservationIgnored private var retune: () -> Void = {}
    @ObservationIgnored private var box: NormRect?
    @ObservationIgnored private var checkedBox: NormRect?
    @ObservationIgnored private var collecting: Stage = .idle
    @ObservationIgnored private var stillFrames: [SetupCalibration.Frame] = []
    @ObservationIgnored private var handFrames: [SetupCalibration.Frame] = []
    @ObservationIgnored private var run: Task<Void, Never>?

    /// `settings` is the cook's own tuning, `retune` re-sends the detector its settings and
    /// arming, both from `CookSession`.
    func connect(
        camera: CameraController,
        settings: @escaping () -> DetectorSettings,
        speak: @escaping (String) -> Void,
        retune: @escaping () -> Void
    ) {
        self.camera = camera
        self.settings = settings
        self.speak = speak
        self.retune = retune
    }

    /// The cook's settings with this box's tuning laid over them.
    func tuned(_ settings: DetectorSettings) -> DetectorSettings {
        tuning?.applied(to: settings) ?? settings
    }

    /// The pan box was confirmed. Uses the tuning saved for it, and checks unless this box
    /// was already checked since launch.
    func panConfirmed(_ box: NormRect) {
        self.box = box
        tuning = Self.saved(for: box)
        if let checkedBox, Self.same(checkedBox, box) {
            retune()
        } else {
            start()
        }
    }

    /// "Check the setup". `possible` is false while there's no confirmed box.
    func checkAgain(possible: Bool) {
        guard possible, box != nil else {
            speak("Draw a box around the pan first.")
            return
        }
        start()
    }

    /// "Skip", or the button: ends the check and keeps the tuning the box had.
    func skip() {
        guard isRunning else { return }
        stop()
        stage = .idle
        retune()
        speak("Skipped.")
    }

    /// Hides the result.
    func dismiss() {
        if case .done = stage { stage = .idle }
    }

    func progress(at date: Date) -> Double {
        min(max(date.timeIntervalSince(startedAt) / Self.finishAt, 0), 1)
    }

    private func start() {
        stop()
        stillFrames = []
        handFrames = []
        startedAt = Date()
        stage = .still
        // Disarmed while it runs (see `CookSession.refreshArming`), so the hand over the pot
        // is never taken for an addition.
        retune()
        speak("Keep your hands away for two seconds.")
        camera?.analyzer.setCalibrationTap { [weak self] frame in
            Task { @MainActor in self?.receive(frame) }
        }
        run = Task { [weak self] in
            await Self.pause(Self.stillFrom)
            self?.collecting = .still
            await Self.pause(Self.handAt - Self.stillFrom)
            guard let self, !Task.isCancelled else { return }
            collecting = .idle
            stage = .hand
            speak("Now hold one hand over the pot.")
            await Self.pause(Self.handFrom - Self.handAt)
            collecting = .hand
            await Self.pause(Self.finishAt - Self.handFrom)
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func receive(_ frame: SetupCalibration.Frame) {
        switch collecting {
        case .still: stillFrames.append(frame)
        case .hand: handFrames.append(frame)
        default: break
        }
    }

    private func finish() {
        stop()
        let result = SetupCalibration.calibrate(still: stillFrames, hand: handFrames, base: settings())
        if !result.findings.contains(.noPicture) {
            tuning = result.tuning
            if let box {
                checkedBox = box
                Self.save(result.tuning, for: box)
            }
        }
        if result.findings.contains(.flicker) {
            // Bands at this exposure: the lights run on the other mains frequency.
            FlickerLock.switchMains()
            camera?.setAdjustmentsLocked(true)
        }
        stage = .done(result)
        retune()
        speak(result.spoken)
        let shown = result
        Task { [weak self] in
            await Self.pause(Self.resultShown)
            if let self, self.stage == .done(shown) { self.stage = .idle }
        }
    }

    private func stop() {
        run?.cancel()
        run = nil
        collecting = .idle
        camera?.analyzer.setCalibrationTap(nil)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Saved per box

    private struct Saved: Codable {
        let box: NormRect
        let tuning: SetupTuning
    }

    private static let savedKey = "setupTuning.v1"

    private static func same(_ a: NormRect, _ b: NormRect) -> Bool {
        abs(a.x - b.x) < 0.03 && abs(a.y - b.y) < 0.03 && abs(a.width - b.width) < 0.03 && abs(a.height - b.height) < 0.03
    }

    private static func saved(for box: NormRect) -> SetupTuning? {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              same(saved.box, box) else { return nil }
        return saved.tuning
    }

    private static func save(_ tuning: SetupTuning, for box: NormRect) {
        UserDefaults.standard.set(try? JSONEncoder().encode(Saved(box: box, tuning: tuning)), forKey: savedKey)
    }
}
