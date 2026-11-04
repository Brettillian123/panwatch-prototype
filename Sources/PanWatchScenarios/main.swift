import Foundation

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
