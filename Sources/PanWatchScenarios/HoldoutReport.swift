import Foundation
@testable import PanWatchCore

/// How one stage went. An add passes if an offer comes within its window and none comes
/// before it; anything else passes only if nothing is offered.
struct Verdict {
    let stage: Stage
    let offers: [Double]
    let visits: Int

    var caught: Double? { offers.first { $0 >= -0.5 && $0 <= stage.window } }
    var passed: Bool { stage.action.isAdd ? caught != nil && !offers.contains { $0 < -0.5 } : offers.isEmpty }
    var got: String {
        if let first = offers.first { return String(format: "offer %+.1fs", first) + (offers.count > 1 ? " +\(offers.count - 1)" : "") }
        return visits == 0 ? "no visit" : "no offer (\(visits) visit\(visits == 1 ? "" : "s"))"
    }

    static func judge(_ stage: Stage) -> Verdict {
        var frames = stage.frames
        let script = frames.script
        var pipeline = FramePipeline(settings: stage.food.settings, region: CounterView.region)
        var decisions: [DetectorDecision] = []
        while let frame = frames.next() {
            if let decision = pipeline.process(frame) { decisions.append(decision) }
        }
        let offers = decisions.filter { $0.outcome == .addition }.map { $0.time - script.eventTime }
        return Verdict(stage: stage, offers: offers, visits: decisions.count)
    }
}

private func cell(_ text: String, _ width: Int) -> String {
    text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
}

private func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "  -" : String(format: "%3.0f%%", 100 * Double(part) / Double(whole))
}

/// Where a metrics file goes: the handoff folder as Windows or WSL sees it, else here.
func handoffMetricsPath(_ file: String) -> String {
    for root in ["/mnt/c/M.A.D/handoff", "C:/M.A.D/handoff"] where FileManager.default.fileExists(atPath: root) {
        return root + "/metrics/" + file
    }
    return file
}

private func write(_ body: [String: Any], to path: String) {
    do {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        print("wrote \(path)")
    } catch {
        print("could not write \(path): \(error)")
    }
}

/// `PanWatchScenarios --holdout`: the hand-written held-out set, in the suite's table and
/// metrics format.
func runHoldout() {
    let verdicts = Stage.holdout().map(Verdict.judge)
    print(cell("situation", 46), cell("step", 10), cell("expected", 9), cell("got", 24), "pass")
    for verdict in verdicts {
        let stage = verdict.stage
        print(
            cell(String(stage.name.dropFirst("holdout/".count)), 46), cell(stage.food.rawValue, 10),
            cell(stage.action.isAdd ? "offer" : "none", 9), cell(verdict.got, 24), verdict.passed ? "yes" : "NO"
        )
    }
    let adds = verdicts.filter(\.stage.action.isAdd), nonAdds = verdicts.filter { !$0.stage.action.isAdd }
    let caught = adds.filter(\.passed).count, falseOffers = nonAdds.filter { !$0.passed }.count
    print("holdout adds caught: \(caught)/\(adds.count)   false offers: \(falseOffers)/\(nonAdds.count) non-add situations")
    var addSet: [String: Bool] = [:], nonAddSet: [String: Bool] = [:]
    for verdict in verdicts {
        let name = String(verdict.stage.name.dropFirst("holdout/".count))
        if verdict.stage.action.isAdd { addSet[name] = verdict.passed } else { nonAddSet[name] = verdict.passed }
    }
    let path = ProcessInfo.processInfo.environment["HOLDOUT_METRICS"] ?? handoffMetricsPath("holdout-r0.json")
    write(["round": 0, "sets": ["adds": addSet, "non-adds": nonAddSet]], to: path)
}

/// `PanWatchScenarios --random 200 [--seed n]`: random situations, each seed in
/// `Stage.stressSeeds` unless one is given, with catch and false-offer rates overall and for
/// every value of every factor, so a weak spot shows even when the average looks fine.
func runStress(count: Int, seeds: [UInt64]) {
    var all: [Verdict] = []
    for seed in seeds {
        let verdicts = Stage.stress(count: count, seed: seed).map(Verdict.judge)
        let adds = verdicts.filter(\.stage.action.isAdd), nonAdds = verdicts.filter { !$0.stage.action.isAdd }
        let caught = adds.filter(\.passed).count, falseOffers = nonAdds.filter { !$0.passed }.count
        print("seed \(seed): adds caught \(caught)/\(adds.count) (\(percent(caught, adds.count)))   "
            + "false offers \(falseOffers)/\(nonAdds.count) (\(percent(falseOffers, nonAdds.count)))")
        all += verdicts
    }
    let adds = all.filter(\.stage.action.isAdd), nonAdds = all.filter { !$0.stage.action.isAdd }
    let caught = adds.filter(\.passed).count, falseOffers = nonAdds.filter { !$0.passed }.count
    print("overall: catch rate \(caught)/\(adds.count) (\(percent(caught, adds.count)))   "
        + "false-offer rate \(falseOffers)/\(nonAdds.count) (\(percent(falseOffers, nonAdds.count)))")

    struct Cell { var adds = 0, caught = 0, nonAdds = 0, falseOffers = 0 }
    var order: [String] = [], values: [String: [String]] = [:], cells: [String: Cell] = [:]
    for verdict in all {
        for (factor, value) in verdict.stage.factors {
            if values[factor] == nil { order.append(factor); values[factor] = [] }
            if !values[factor]!.contains(value) { values[factor]!.append(value) }
            var c = cells[factor + "|" + value] ?? Cell()
            if verdict.stage.action.isAdd {
                c.adds += 1
                if verdict.passed { c.caught += 1 }
            } else {
                c.nonAdds += 1
                if !verdict.passed { c.falseOffers += 1 }
            }
            cells[factor + "|" + value] = c
        }
    }
    print(cell("factor", 16), cell("value", 30), cell("caught", 15), "false offers")
    var rows: [(String, Double, Cell)] = []
    var json: [String: Any] = [:]
    for factor in order {
        var byValue: [String: Any] = [:]
        for value in values[factor]!.sorted() {
            let c = cells[factor + "|" + value]!
            print(cell(factor, 16), cell(value, 30), cell("\(c.caught)/\(c.adds) \(percent(c.caught, c.adds))", 15),
                  "\(c.falseOffers)/\(c.nonAdds) \(percent(c.falseOffers, c.nonAdds))")
            byValue[value] = ["adds": c.adds, "caught": c.caught, "non-adds": c.nonAdds, "false offers": c.falseOffers]
            // Weakness: the share of situations it got wrong, once there are enough to say.
            if c.adds + c.nonAdds >= 12 {
                let missRate = c.adds > 0 ? Double(c.adds - c.caught) / Double(c.adds) : 0
                let falseRate = c.nonAdds > 0 ? Double(c.falseOffers) / Double(c.nonAdds) : 0
                rows.append(("\(factor): \(value)", (missRate + falseRate) / 2, c))
            }
        }
        json[factor] = byValue
    }
    print("weakest (mean of miss rate and false-offer rate, 12+ situations):")
    for (name, score, c) in rows.sorted(by: { $0.1 > $1.1 }).prefix(3) {
        print("  \(name)  caught \(c.caught)/\(c.adds)  false offers \(c.falseOffers)/\(c.nonAdds)  (\(String(format: "%.0f%%", 100 * score)) wrong)")
    }
    let path = ProcessInfo.processInfo.environment["STRESS_METRICS"] ?? handoffMetricsPath("holdout-stress-r0.json")
    write([
        "round": 0, "count": count, "seeds": seeds.map(String.init), "adds": adds.count, "caught": caught,
        "non-adds": nonAdds.count, "false offers": falseOffers, "by factor": json,
    ], to: path)
}
