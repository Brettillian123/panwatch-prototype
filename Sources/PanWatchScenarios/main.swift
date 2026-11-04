import Foundation
@testable import PanWatchCore

// Scores the detector on synthetic kitchen situations seen from a phone on the counter.
// A report, not a gate: it always exits 0.

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

if let flag = CommandLine.arguments.firstIndex(of: "--explain"), flag + 1 < CommandLine.arguments.count {
    let wanted = CommandLine.arguments[flag + 1]
    for run in Run.suite() where run.name == wanted {
        print(explain(RunResult.evaluate(run)))
        if CommandLine.arguments.contains("--trace") { print(trace(run)) }
    }
    exit(0)
}

if CommandLine.arguments.contains("--diagnose") {
    for run in Run.suite() {
        var frames = ScenarioFrames(run: run)
        var pipeline = FramePipeline(settings: run.step.settings, region: CounterView.region)
        var path: [String] = [], lines: [String] = []
        var index = 0
        while let frame = frames.next() {
            let decision = pipeline.process(frame)
            let t = frame.time - frames.script.eventTime
            if let d = decision, t >= -1 {
                let rule = run.step.settings.changeRule
                lines.append(String(
                    format: "   %@ %+.1f chg %.3f s2 %.3f s4 %.3f sh %.0f dw %.1f op %.2f", d.outcome.rawValue, t, d.changedFraction,
                    d.after.structureChange(from: d.before, rule: rule, radius: 2), d.after.structureChange(from: d.before, rule: rule, radius: 4),
                    d.medianLumaShift, d.dwell, d.handOpened
                ))
            }
            if t >= -1, t <= 3, index % 3 == 0 {
                path.append(pipeline.last.handPoint.map { String(format: "%.2f,%.2f", $0.x, $0.y) } ?? "-")
            }
            index += 1
        }
        print("\(run.name) [\(run.step.rawValue)] " + path.joined(separator: " "))
        lines.forEach { print($0) }
    }
    exit(0)
}

if CommandLine.arguments.contains("--holdout") {
    runHoldout()
    exit(0)
}

if let flag = CommandLine.arguments.firstIndex(of: "--random") {
    let arguments = CommandLine.arguments
    let count = flag + 1 < arguments.count ? Int(arguments[flag + 1]) ?? 200 : 200
    let seeds = arguments.firstIndex(of: "--seed").flatMap { $0 + 1 < arguments.count ? UInt64(arguments[$0 + 1]) : nil }
        .map { [$0] } ?? Stage.stressSeeds
    runStress(count: count, seeds: seeds)
    exit(0)
}

let results = Run.suite().map(RunResult.evaluate)

print(pad("situation", 20), pad("environment", 12), pad("step", 7), pad("expected", 9), pad("got", 46), pad("time", 6), "pass")
for result in results {
    let run = result.run
    let time = result.shownTime.map { String(format: "%+.1fs", $0) } ?? "-"
    print(
        pad(run.kind.rawValue, 20), pad(run.environment.name, 12), pad(run.step.rawValue, 7),
        pad(run.kind.isAdd ? "offer" : "none", 9), pad(result.got, 46), pad(time, 6), result.passed ? "yes" : "NO"
    )
}

let adds = results.filter(\.run.kind.isAdd), nonAdds = results.filter { !$0.run.kind.isAdd }
let caught = adds.filter(\.passed).count
let falseOffers = nonAdds.filter { !$0.passed }.count
print("adds caught: \(caught)/\(adds.count)   false offers: \(falseOffers)/\(nonAdds.count) non-add situations")
for environment in [Environment.brightWood, .dimGranite, .ledSteel, .whiteSteel] {
    let here = results.filter { $0.run.environment.name == environment.name }
    print("  \(pad(environment.name, 12)) passed \(here.filter(\.passed).count)/\(here.count)")
}

let path = metricsPath(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
do {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try metricsJSON(results).write(to: url)
    print("wrote \(path)")
} catch {
    print("could not write \(path): \(error)")
}
