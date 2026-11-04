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

    let run: Run
    let script: Script
    let view: CounterView
    let count: Int
    private var renderer: SceneRenderer
    private var random: SeededRandom
    private var index = 0

    init(run: Run) {
        self.run = run
        script = run.script()
        view = CounterView(vessel: run.vessel)
        count = Int((run.duration * Self.rate).rounded())
        renderer = SceneRenderer(view: view, environment: run.environment, seed: run.name)
        random = SeededRandom(name: run.name + "/vision")
    }

    mutating func next() -> SyntheticFrame? {
        guard index < count else { return nil }
        let t = Double(index) / Self.rate
        var vision: [VisionHand] = []
        var painted: [PaintedHand] = []
        for track in script.hands {
            if let seen = track.observe(at: t, in: run.environment, random: &random) { vision.append(seen) }
            if let paint = track.painted(at: t, in: view) { painted.append(paint) }
        }
        let patch = renderer.render(script.scene(t), hands: painted, frame: index)
        index += 1
        return SyntheticFrame(time: t, vision: vision, patch: patch)
    }
}

/// The app's per-frame flow, step for step as `FrameAnalyzer.captureOutput` runs it: Vision's
/// hands through the app's checks, then `HandFilter`, the zone around the pan, the openness of
/// a lone hand, then `AdditionDetector`. Everything a frame goes through is in `process`, so it
/// can be swapped for a shared replay pipeline without touching the scenarios.
struct FramePipeline {
    let settings: DetectorSettings
    let region: NormRect
    private(set) var detector: AdditionDetector
    private var handFilter: HandFilter

    init(settings: DetectorSettings, region: NormRect) {
        self.settings = settings
        self.region = region
        detector = AdditionDetector(settings: settings)
        detector.setArmed(true)
        handFilter = HandFilter(settings: settings)
    }

    mutating func process(_ frame: SyntheticFrame) -> DetectorDecision? {
        let seen = trackedHands(frame.vision, settings: settings)
        let filtered = handFilter.update(seen.map { HandGeometry.centroid($0.joints) }, at: frame.time)
        let hands = filtered.counted.map { seen[$0] }
        // Three joints, not one: a fingertip grazing the edge of the zone isn't a visit.
        let zone = region.expanded(by: settings.handZoneMargin)
        let inZone = hands.filter { HandGeometry.anyHand([$0.joints], in: zone, minimumJoints: 3) }
        // With two hands over the pan, there's no telling which one let go.
        let openness = inZone.count == 1 ? inZone[0].openness : nil
        let observation = FrameObservation(time: frame.time, handInZone: !inZone.isEmpty, handOpenness: openness, region: frame.patch)
        return detector.process(observation)
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
    var filter = HandFilter(settings: settings)
    var lines: [String] = []
    while let frame = frames.next() {
        let gated = trackedHands(frame.vision, settings: settings)
        let counted = filter.update(gated.map { HandGeometry.centroid($0.joints) }, at: frame.time).counted.count
        let decision = pipeline.process(frame)
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
