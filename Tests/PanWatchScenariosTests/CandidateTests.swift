import Testing
@testable import PanWatchCore
@testable import PanWatchScenarios

/// AI confirm: the candidate rules against the scenario suite, with the model mocked.
struct CandidateTests {
    /// Every add but one gets a candidate. In dim light Vision sees the partial hand on tongs in
    /// about one frame in four, so no visit lasts, and the pot shows too little change.
    @Test func candidatesReachEveryAddInTheSuite() {
        let unseen: Set<String> = ["tongs, dim granite"]
        for run in Run.suite() where run.kind.isAdd && !unseen.contains(run.name) {
            let result = CheckedRun.evaluate(run, verifier: .perfect)
            #expect(result.reached, "no candidate for \(run.name)")
        }
    }

    @Test func withoutTheModelTheSuiteScoresExactlyAsTodaysRules() {
        for run in Run.suite() {
            let today = RunResult.evaluate(run)
            let checked = CheckedRun.evaluate(run, verifier: .none)
            #expect(checked.offers == today.offers, "\(run.name) changed without the model")
            #expect(checked.checks == 0)
        }
    }

    @Test func aRightModelLeavesNoFalseOffers() {
        for run in Run.suite() where !run.kind.isAdd {
            #expect(CheckedRun.evaluate(run, verifier: .perfect).offers.isEmpty, "\(run.name) offered")
        }
    }
}
