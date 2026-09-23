import Testing
@testable import PanWatchCore

@Suite("Addition detector")
struct AdditionDetectorTests {
    /// Learn the empty pan, reach in, pull the arm out, and let the pan settle on `after`.
    private func visit(settlingOn after: PanPatch, handSeconds: Double = 1.2) -> Timeline {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(handSeconds, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)          // arm still moving out, hand no longer tracked
        timeline.hold(1.5, patch: after)
        return timeline
    }

    @Test func reportsAClearAddition() throws {
        let results = decisions(for: visit(settlingOn: Pans.withPasta))
        #expect(results.count == 1)
        let decision = try #require(results.first)
        #expect(decision.outcome == .addition)
        #expect(abs(decision.changedFraction - 0.25) < 0.001)
        #expect(decision.settledCleanly)
        #expect(decision.dwell > 1.0)
        #expect(decision.before == Pans.empty)
        #expect(decision.after == Pans.withPasta)
    }

    @Test func stirringThatLeavesThePanAloneIsNotAnAddition() {
        let results = decisions(for: visit(settlingOn: Pans.empty))
        #expect(results.map(\.outcome) == [.noChange])
    }

    @Test func aHandPassingOverIsIgnored() {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(0.13, hand: true, patch: Pans.arm)
        timeline.hold(2.0, patch: Pans.empty)
        #expect(decisions(for: timeline).isEmpty)
    }

    @Test func aLightSwitchingOnIsVetoed() {
        let results = decisions(for: visit(settlingOn: Pans.brighter))
        #expect(results.map(\.outcome) == [.lightingChange])
    }

    @Test func turningTheVetoOffLetsLightingThrough() {
        var settings = DetectorSettings()
        settings.lightingVeto = false
        let results = decisions(for: visit(settlingOn: Pans.brighter), settings: settings)
        #expect(results.map(\.outcome) == [.addition])
    }

    @Test func staysQuietWhenTheStepIsNotWatched() {
        #expect(decisions(for: visit(settlingOn: Pans.withPasta), armed: false).isEmpty)
    }

    @Test func aHandComingBackWhileSettlingIsOneVisit() throws {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(0.6, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)          // long enough to start settling
        timeline.hold(0.5, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)
        timeline.hold(1.5, patch: Pans.withPasta)
        let results = decisions(for: timeline)
        #expect(results.count == 1)
        let decision = try #require(results.first)
        #expect(decision.outcome == .addition)
        #expect(decision.dwell > 0.9)
    }

    @Test func aPanThatNeverSettlesIsJudgedAtTheTimeLimit() throws {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(1.0, hand: true, patch: Pans.arm)
        // Bubbles: part of the pan flickers every frame, forever.
        timeline.hold(5.0) { index in
            index.isMultiple(of: 2) ? Pans.withPasta : Pans.withPasta.painting(x: 20..<28, y: 20..<28, luma: 120)
        }
        let results = decisions(for: timeline)
        #expect(results.count == 1)
        let decision = try #require(results.first)
        #expect(decision.outcome == .addition)
        #expect(!decision.settledCleanly)
    }

    @Test func motionAloneStartsAVisitWhenHandsAreNotRequired() {
        var settings = DetectorSettings()
        settings.requireHand = false
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(1.0, patch: Pans.arm)          // no hand reported, only motion
        timeline.hold(1.5, patch: Pans.withPasta)
        #expect(decisions(for: timeline, settings: settings).map(\.outcome) == [.addition])
        #expect(decisions(for: timeline).isEmpty)
    }

    @Test func cooldownSwallowsAnImmediateSecondVisit() {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(1.0, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)
        timeline.hold(1.0, patch: Pans.withPasta)    // first decision lands here
        timeline.hold(0.8, hand: true, patch: Pans.withPasta)   // within the cooldown
        timeline.hold(3.0, patch: Pans.withPasta)
        timeline.hold(1.0, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)
        timeline.hold(1.5, patch: Pans.withMore)
        let results = decisions(for: timeline)
        #expect(results.map(\.outcome) == [.addition, .addition])
        // The second visit is compared with the pan that already had pasta in it.
        #expect(results.last?.before == Pans.withPasta)
    }

    @Test func warmUpWaitsWhileAHandIsInThePan() {
        var detector = AdditionDetector()
        detector.setArmed(true)
        var timeline = Timeline()
        timeline.hold(2.0, hand: true, patch: Pans.arm)
        for frame in timeline.frames { _ = detector.process(frame) }
        #expect(detector.phase == .warmingUp)
    }

    @Test func disarmingMidVisitDropsIt() {
        var detector = AdditionDetector()
        detector.setArmed(true)
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(0.8, hand: true, patch: Pans.arm)
        for frame in timeline.frames { _ = detector.process(frame) }
        #expect(detector.phase == .handInPan)

        detector.setArmed(false)
        #expect(detector.phase == .disarmed)
        detector.setArmed(true)
        #expect(detector.phase == .warmingUp)
    }
}
