import Foundation
@testable import PanWatchCore

// AI confirm: `swift run -c release PanWatchScenarios --verifier perfect|none`. Runs the
// suite through today's rules, the looser candidate rules and the gate, with the on-device
// model stood in by a mock. `perfect` knows the truth, so it gives the ceiling: how many adds
// the candidates reach, and how many false offers remain if the model is always right.
// `none` is a phone without the model: today's rules exactly.

enum MockVerifier: String {
    case perfect, none
}

/// One run through the rules, the candidate rules and the gate.
struct CheckedRun {
    let run: Run
    let eventTime: Double
    /// Offer times, in seconds from the start of the event.
    var offers: [Double] = []
    /// Times the rules or the candidate rules proposed an add, from the start of the event.
    var proposals: [Double] = []
    /// Checks sent to the model.
    var checks = 0

    var caught: Double? { offers.first { $0 >= -0.5 && $0 <= run.kind.window } }

    var passed: Bool {
        run.kind.isAdd ? caught != nil && !offers.contains { $0 < -0.5 } : offers.isEmpty
    }

    /// A proposal fell inside the add's window, so a right model could offer it.
    var reached: Bool { proposals.contains { $0 >= -0.5 && $0 <= run.kind.window } }

    static func evaluate(_ run: Run, verifier: MockVerifier) -> CheckedRun {
        var frames = ScenarioFrames(run: run)
        var watcher = PanWatcher(settings: run.step.settings)
        watcher.proposesCandidates = verifier != .none
        var gate = AddConfirmGate()
        gate.checking = verifier != .none
        var result = CheckedRun(run: run, eventTime: frames.script.eventTime)
        let event = result.eventTime
        while let frame = frames.next() {
            let seen = watcher.process(
                time: frame.time, hands: frame.vision.map(\.reading), aspect: CounterView.aspect,
                region: CounterView.region, patch: frame.patch, armed: true
            )
            if seen.candidate != nil || seen.decision?.outcome == .addition { result.proposals.append(frame.time - event) }
            if seen.handInZone { gate.noteHand(at: frame.time) }
            let step = gate.receive(rules: seen.decision, candidate: seen.candidate, at: frame.time, context: run.step.rawValue)
            if step.offer != nil { result.offers.append(frame.time - event) }
            if let check = step.ask {
                result.checks += 1
                // The perfect model answers at once and knows whether a hand is adding now.
                let since = check.time - event
                let adding = run.kind.isAdd && since >= -0.5 && since <= run.kind.window
                let verdict = AddVerdict(adding: adding, food: adding ? run.step.rawValue : "", confidence: 1)
                if gate.answer(check.id, .verdict(verdict))?.offer != nil { result.offers.append(frame.time - event) }
            }
        }
        return result
    }
}

func runVerifier(_ verifier: MockVerifier) {
    let results = Run.suite().map { CheckedRun.evaluate($0, verifier: verifier) }
    print(pad("situation", 20), pad("environment", 12), pad("step", 7), pad("expected", 9), pad("reached", 8), pad("checks", 7), "pass")
    for result in results {
        let run = result.run
        print(
            pad(run.kind.rawValue, 20), pad(run.environment.name, 12), pad(run.step.rawValue, 7),
            pad(run.kind.isAdd ? "offer" : "none", 9), pad(result.reached ? "yes" : "no", 8), pad("\(result.checks)", 7),
            result.passed ? "yes" : "NO"
        )
    }
    let adds = results.filter(\.run.kind.isAdd), nonAdds = results.filter { !$0.run.kind.isAdd }
    let missed = adds.filter { !$0.passed }.map(\.run.name)
    let proposed = nonAdds.filter { !$0.proposals.isEmpty }
    print("missed adds: " + (missed.isEmpty ? "none" : missed.joined(separator: "; ")))
    print("non-add situations the model must turn down: \(proposed.count)/\(nonAdds.count), \(proposed.map(\.checks).reduce(0, +)) checks")
    print("checks per add situation: \(adds.map(\.checks).reduce(0, +)) for \(adds.count) adds")
    print("verifier \(verifier.rawValue): adds reached by candidates \(adds.filter(\.reached).count)/\(adds.count)")
    print("verifier \(verifier.rawValue): adds caught \(adds.filter(\.passed).count)/\(adds.count)   false offers \(nonAdds.filter { !$0.passed }.count)/\(nonAdds.count)")
}
