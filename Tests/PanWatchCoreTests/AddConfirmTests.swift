import Testing
@testable import PanWatchCore

/// AI confirm: the gate between the rules and the offer, with the model mocked.
struct AddConfirmTests {
    private func decision(_ outcome: DetectorDecision.Outcome = .addition, at time: Double) -> DetectorDecision {
        DetectorDecision(
            id: Int(time * 10), time: time, outcome: outcome, changedFraction: 0.1, additionThreshold: 0.03,
            medianLumaShift: 0, dwell: 1, handOpened: 0, released: false, settledCleanly: true,
            before: Pans.empty, after: Pans.withPasta
        )
    }

    private func checkingGate() -> AddConfirmGate {
        var gate = AddConfirmGate()
        gate.checking = true
        return gate
    }

    private let yes = AddVerdict(adding: true, food: "pasta", confidence: 0.9)

    /// Unwraps outside the macro, which can't take a mutating call.
    private func need<T>(_ value: T?) throws -> T { try #require(value) }

    @Test func withoutTheModelTodaysRulesPassStraightThrough() {
        var gate = AddConfirmGate()
        let rules = decision(at: 5)
        let step = gate.receive(rules: rules, candidate: decision(at: 5), at: 5, context: "")
        #expect(step.offer?.id == rules.id)
        #expect(step.ask == nil)
        let alone = gate.receive(rules: decision(.noChange, at: 9), candidate: decision(at: 9), at: 9, context: "")
        #expect(alone.offer == nil && alone.ask == nil)
    }

    @Test func aCandidateIsNotAnOfferUntilTheModelSaysYes() throws {
        var gate = checkingGate()
        let step = gate.receive(rules: nil, candidate: decision(at: 5), at: 5, context: "The recipe step says: Add the pasta.")
        #expect(step.offer == nil)
        let check = try need(step.ask)
        #expect(check.context == "The recipe step says: Add the pasta.")
        let outcome = try need(gate.answer(check.id, .verdict(yes)))
        #expect(outcome.resolution == .confirmed)
        #expect(outcome.offer != nil)
    }

    @Test func aNoAnswerSuppressesTheOffer() throws {
        var gate = checkingGate()
        // Today's rules would offer, but the model says no.
        let check = try need(gate.receive(rules: decision(at: 5), candidate: decision(at: 5), at: 5, context: "").ask)
        let outcome = try need(gate.answer(check.id, .verdict(AddVerdict(adding: false, food: "", confidence: 0.95))))
        #expect(outcome.resolution == .declined)
        #expect(outcome.offer == nil)
        // A rules offer right after the same visit joins the judged check and stays quiet.
        let later = gate.receive(rules: decision(at: 6), candidate: nil, at: 6, context: "")
        #expect(later.offer == nil && later.ask == nil)
    }

    @Test func anUnsureYesDoesNotOffer() throws {
        var gate = checkingGate()
        let check = try need(gate.receive(rules: nil, candidate: decision(at: 5), at: 5, context: "").ask)
        let outcome = try need(gate.answer(check.id, .verdict(AddVerdict(adding: true, food: "pasta", confidence: 0.3))))
        #expect(outcome.resolution == .unsure)
        #expect(outcome.offer == nil)
    }

    @Test func aTimeoutFallsBackToTheRules() throws {
        var gate = checkingGate()
        // The rules offered: on timeout, they decide, and it is offered.
        let check = try need(gate.receive(rules: decision(at: 5), candidate: nil, at: 5, context: "").ask)
        do { let value = gate.tick(at: 7.9); #expect(value == nil) }
        let late = gate.receive(rules: nil, candidate: nil, at: 8.1, context: "")
        #expect(late.ended?.resolution == .timedOut)
        #expect(late.offer != nil)
        // The answer arriving after the timeout is dropped.
        do { let value = gate.answer(check.id, .verdict(yes)); #expect(value == nil) }

        // Only a candidate: the rules didn't offer, so neither does the timeout...
        let candidate = try need(gate.receive(rules: nil, candidate: decision(at: 20), at: 20, context: "").ask)
        let ended = try need(gate.answer(candidate.id, .timedOut))
        #expect(ended.offer == nil)
        // ...unless the rules offer for the same add a moment later.
        do { let value = gate.receive(rules: decision(at: 21), candidate: nil, at: 21, context: "").offer; #expect(value != nil) }
    }

    @Test func anErrorFallsBackToTheRules() throws {
        var gate = checkingGate()
        let check = try need(gate.receive(rules: decision(at: 5), candidate: decision(at: 5), at: 5, context: "").ask)
        let outcome = try need(gate.answer(check.id, .failed))
        #expect(outcome.resolution == .failed)
        #expect(outcome.offer != nil)
    }

    @Test func staleAnswersAreDropped() throws {
        var gate = checkingGate()
        _ = gate.setStep(1)
        let check = try need(gate.receive(rules: decision(at: 5), candidate: nil, at: 5, context: "").ask)
        let stale = try need(gate.setStep(2))
        #expect(stale.resolution == .stale)
        #expect(stale.offer == nil)
        do { let value = gate.answer(check.id, .verdict(yes)); #expect(value == nil) }
        do { let value = gate.pending; #expect(value == nil) }
    }

    @Test func twoCandidatesCloseTogetherMakeOneCheck() throws {
        var gate = checkingGate()
        let first = try need(gate.receive(rules: nil, candidate: decision(at: 5), at: 5, context: "").ask)
        let second = gate.receive(rules: decision(at: 6), candidate: decision(at: 6), at: 6, context: "")
        #expect(second.ask == nil && second.offer == nil)
        #expect(gate.pending?.joined == 1)
        #expect(gate.pending?.rulesOffered == true)
        let outcome = try need(gate.answer(first.id, .verdict(yes)))
        #expect(outcome.offer != nil)
        // Still the same add: no second check, no second offer.
        let third = gate.receive(rules: nil, candidate: decision(at: 7), at: 7, context: "")
        #expect(third.ask == nil && third.offer == nil)
        // Much later, a new add gets a check of its own.
        do { let value = gate.receive(rules: nil, candidate: decision(at: 15), at: 15, context: "").ask; #expect(value != nil) }
    }

    @Test func keyframesKeepArrivalReleaseLeavingAndAfter() {
        var frames = Keyframes<Int>()
        var captures = 0
        func feed(_ time: Double, hand: Bool, y: Double = 0.3, released: Bool = false) {
            frames.observe(time: time, handInZone: hand, handPoint: hand ? NormPoint(x: 0.5, y: y) : nil, released: released) {
                captures += 1
                return Int((time * 100).rounded())
            }
        }
        feed(0.9, hand: false)
        feed(1.0, hand: true, y: 0.3)
        feed(1.25, hand: true, y: 0.5)
        feed(1.5, hand: true, y: 0.6, released: true)
        feed(1.75, hand: true, y: 0.7)
        feed(2.0, hand: true, y: 0.4)
        feed(2.25, hand: false)
        #expect(captures <= 5)
        let taken = frames.take(at: 3, after: 300)
        #expect(taken.map(\.moment) == [.arriving, .release, .leaving, .after])
        #expect(taken.map(\.image) == [100, 150, 200, 300])
        #expect(frames.held.isEmpty)
    }

    @Test func oldHandFramesAreLeftOut() {
        var frames = Keyframes<Int>()
        frames.observe(time: 1, handInZone: true, handPoint: NormPoint(x: 0.5, y: 0.5), released: false) { 1 }
        let taken = frames.take(at: 30, after: 2)
        #expect(taken.map(\.moment) == [.after])
    }
}
