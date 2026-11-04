import Foundation
@testable import PanWatchCore

/// One analyzed frame of a scenario: what Vision saw, and the pan box's picture.
struct SyntheticFrame {
    var time: Double
    var vision: [VisionHand]
    var patch: PanPatch
}

/// A run's frames at 15 fps, the rate the app analyzes at.
struct ScenarioFrames: Sequence, IteratorProtocol {
    static let rate = 15.0

    let script: Script
    let view: CounterView
    let count: Int
    private let environment: Environment
    private var renderer: SceneRenderer
    private var random: SeededRandom
    private var index = 0

    init(run: Run) {
        self.init(name: run.name, script: run.script(), view: CounterView(vessel: run.vessel), environment: run.environment, duration: run.duration)
    }

    /// Any scripted situation: the name seeds the picture and what Vision sees.
    init(name: String, script: Script, view: CounterView, environment: Environment, duration: Double) {
        self.script = script
        self.view = view
        self.environment = environment
        count = Int((duration * Self.rate).rounded())
        renderer = SceneRenderer(view: view, environment: environment, seed: name)
        random = SeededRandom(name: name + "/vision")
    }

    mutating func next() -> SyntheticFrame? {
        guard index < count else { return nil }
        let t = Double(index) / Self.rate
        var vision: [VisionHand] = []
        var painted: [PaintedHand] = []
        for track in script.hands {
            if let seen = track.observe(at: t, in: environment, random: &random) { vision.append(seen) }
            if let paint = track.painted(at: t, in: view) { painted.append(paint) }
        }
        let patch = renderer.render(script.scene(t), hands: painted, frame: index)
        index += 1
        return SyntheticFrame(time: t, vision: vision, patch: patch)
    }
}

/// The app's per-frame flow: Vision's hands, as `HandReading`s, through `PanWatcher`, the
/// same code `FrameAnalyzer.captureOutput` and the practice replay run, so the suite
/// measures the real app.
struct FramePipeline {
    let settings: DetectorSettings
    let region: NormRect
    private var watcher: PanWatcher
    var detector: AdditionDetector { watcher.detector }
    /// What the watcher made of the latest frame, for tracing.
    private(set) var last = PanWatcher.Result()

    init(settings: DetectorSettings, region: NormRect) {
        self.settings = settings
        self.region = region
        watcher = PanWatcher(settings: settings)
    }

    mutating func process(_ frame: SyntheticFrame) -> DetectorDecision? {
        last = watcher.process(
            time: frame.time, hands: frame.vision.map(\.reading), aspect: CounterView.aspect,
            region: region, patch: frame.patch, armed: true
        )
        return last.decision
    }
}

/// How one run went.
struct RunResult {
    let run: Run
    let eventTime: Double
    let decisions: [DetectorDecision]

    /// Offer times, in seconds from the start of the event.
    var offers: [Double] { decisions.filter { $0.outcome == .addition }.map { $0.time - eventTime } }

    /// The first offer that answers the add, if any.
    var caught: Double? { offers.first { $0 >= -0.5 && $0 <= run.kind.window } }

    var passed: Bool {
        run.kind.isAdd ? caught != nil && !offers.contains { $0 < -0.5 } : offers.isEmpty
    }

    /// The seconds shown in the table: how long the add took to be offered, or when the false offer came.
    var shownTime: Double? { run.kind.isAdd ? caught : offers.first }

    /// What the detector made of it, with the numbers that decided it.
    var got: String {
        let relevant = decisions.filter { $0.time >= eventTime - 1 }
        guard !relevant.isEmpty else { return decisions.isEmpty ? "no visit" : "no visit after event" }
        let shown = relevant.first { $0.outcome == .addition } ?? relevant[0]
        let name = shown.outcome == .addition ? (shown.released ? "offer(release)" : "offer") : shown.outcome.rawValue
        let more = relevant.count > 1 ? " +\(relevant.count - 1)" : ""
        return String(
            format: "%@ chg %.3f/%.2f dw %.1f op %.2f%@",
            name, shown.changedFraction, shown.additionThreshold, shown.dwell, shown.handOpened, more
        )
    }

    static func evaluate(_ run: Run) -> RunResult {
        var frames = ScenarioFrames(run: run)
        var pipeline = FramePipeline(settings: run.step.settings, region: CounterView.region)
        var decisions: [DetectorDecision] = []
        while let frame = frames.next() {
            if let decision = pipeline.process(frame) { decisions.append(decision) }
        }
        return RunResult(run: run, eventTime: frames.script.eventTime, decisions: decisions)
    }
}

/// Where the round's metrics go: the first argument, else `SCENARIO_METRICS`, else the
/// handoff folder as Windows or WSL sees it.
func metricsPath(arguments: [String], environment: [String: String]) -> String {
    if arguments.count > 1 { return arguments[1] }
    if let path = environment["SCENARIO_METRICS"] { return path }
    for root in ["/mnt/c/M.A.D/handoff", "C:/M.A.D/handoff"] where FileManager.default.fileExists(atPath: root) {
        return root + "/metrics/scenarios-r1.json"
    }
    return "scenarios-r1.json"
}

func metricsJSON(_ results: [RunResult]) throws -> Data {
    var adds: [String: Bool] = [:], nonAdds: [String: Bool] = [:]
    for result in results {
        if result.run.kind.isAdd { adds[result.run.name] = result.passed } else { nonAdds[result.run.name] = result.passed }
    }
    let body: [String: Any] = ["round": 1, "sets": ["adds": adds, "non-adds": nonAdds]]
    return try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
}

/// Draws a decision's before and after pictures and what changed, as text, for working out
/// why a run went the way it did. `swift run PanWatchScenarios --explain "tasting, white steel"`.
func explain(_ result: RunResult) -> String {
    let ramp = Array(" .:-=+*#%@")
    var lines = ["\(result.run.name) (\(result.run.step.rawValue)): \(result.got)"]
    for decision in result.decisions {
        let mask = decision.after.changedMask(from: decision.before, rule: result.run.step.settings.changeRule) ?? []
        lines.append(String(
            format: "%@ at %+.2fs  changed %.3f  luma shift %.1f  dwell %.2f  opened %.2f",
            decision.outcome.rawValue, decision.time - result.eventTime, decision.changedFraction,
            decision.medianLumaShift, decision.dwell, decision.handOpened
        ))
        lines.append("before" + String(repeating: " ", count: decision.before.width - 6) + " | after"
            + String(repeating: " ", count: decision.after.width - 5) + " | changed")
        for row in 0..<decision.before.height {
            func picture(_ patch: PanPatch) -> String {
                String((0..<patch.width).map { ramp[Int(patch.luma[row * patch.width + $0]) * ramp.count / 256] })
            }
            let changed = String((0..<decision.before.width).map { mask.isEmpty ? "?" : mask[row * decision.before.width + $0] ? "X" : "." })
            lines.append(picture(decision.before) + " | " + picture(decision.after) + " | " + changed)
        }
    }
    return lines.joined(separator: "\n")
}

/// Frame by frame around the event: hands Vision reported, hands past the app's checks, hands
/// the filter counted, whether one was in the zone, its openness, and the detector's phase.
func trace(_ run: Run, from start: Double = -1, to stop: Double = 3) -> String {
    var frames = ScenarioFrames(run: run)
    let settings = run.step.settings
    var pipeline = FramePipeline(settings: settings, region: CounterView.region)
    var lines: [String] = []
    while let frame = frames.next() {
        let decision = pipeline.process(frame)
        let gated = pipeline.last.seen
        let counted = pipeline.last.handsCounted
        let t = frame.time - frames.script.eventTime
        guard t >= start, t <= stop else { continue }
        let joints = frame.vision.map { "\($0.joints.count)@\(String(format: "%.2f", $0.confidence))" }.joined(separator: ",")
        let openness = gated.compactMap(\.openness).map { String(format: "%.2f", $0) }.joined(separator: ",")
        lines.append(String(
            format: "%+.2f vision[%@] passed %d counted %d open[%@] %@%@",
            t, joints, gated.count, counted, openness, "\(pipeline.detector.phase)",
            decision.map { " -> \($0.outcome.rawValue)" } ?? ""
        ))
    }
    return lines.joined(separator: "\n")
}
