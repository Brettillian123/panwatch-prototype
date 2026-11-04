import Testing
@testable import PanWatchCore

/// The rules added by `detect-tune`: where the hand was, how long the visit spanned, and
/// whether the box's structure changed under a change of light.
@Suite("Detector tuning")
struct DetectTuneTests {
    /// Minced garlic: a hand visit is enough, so only the hand's behavior can rule one out.
    private var garlic: DetectorSettings {
        var settings = DetectorSettings()
        settings.additionThreshold = 0
        return settings
    }

    /// Learn the empty pan, hold a hand at `place` (relative to the box) for 1.2 s, and settle.
    private func visit(at place: NormPoint) -> [FrameObservation] {
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(1.2, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)
        timeline.hold(1.5, patch: Pans.empty)
        return timeline.frames.map { frame in
            var frame = frame
            if frame.handInZone { frame.handPoint = place }
            return frame
        }
    }

    private func outcomes(_ frames: [FrameObservation], settings: DetectorSettings) -> [DetectorDecision.Outcome] {
        var detector = AdditionDetector(settings: settings)
        detector.setArmed(true)
        return frames.compactMap { detector.process($0) }.map(\.outcome)
    }

    @Test func aHandOverTheOpeningCounts() {
        #expect(outcomes(visit(at: NormPoint(x: 0.5, y: -0.1)), settings: garlic) == [.addition])
    }

    @Test func aHandAtThePansEdgeIsNotAVisit() {
        // Holding the handle at the box's right edge, or resting on the counter to its left.
        #expect(outcomes(visit(at: NormPoint(x: 0.96, y: 0.55)), settings: garlic).isEmpty)
        #expect(outcomes(visit(at: NormPoint(x: -0.08, y: 0.83)), settings: garlic).isEmpty)
    }

    @Test func aStirBrokenUpByDimLightIsStillStirring() {
        // Ten seconds of stirring with the hand lost every other 0.3 s: under six seconds of
        // counted hand, but the visit spans ten.
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        for _ in 0..<17 {
            timeline.hold(0.3, hand: true, patch: Pans.arm)
            timeline.hold(0.3, patch: Pans.arm)
        }
        timeline.hold(2.0, patch: Pans.empty)
        #expect(outcomes(timeline.frames, settings: garlic) == [.stirring])
    }

    @Test func foodLandingAsTheLightChangesIsNotVetoed() {
        // The pan brightens evenly, and a patch of pasta lands in one corner: the light alone
        // would be vetoed, but the pasta changes the box's structure.
        var after = Pans.brighter
        for y in 0..<8 {
            for x in 0..<8 where (x + y) % 2 == 0 { after.luma[y * Pans.side + x] = 170 }
        }
        var timeline = Timeline()
        timeline.hold(1.0, patch: Pans.empty)
        timeline.hold(1.2, hand: true, patch: Pans.arm)
        timeline.hold(0.6, patch: Pans.arm)
        timeline.hold(1.5, patch: after)
        #expect(outcomes(timeline.frames, settings: DetectorSettings()) == [.addition])
    }

    @Test func structureIgnoresSmoothShading() {
        let rule = DetectorSettings().changeRule
        // An even light and a soft shadow change no structure; a textured patch does.
        #expect(Pans.brighter.structureChange(from: Pans.empty, rule: rule, radius: 4) == 0)
        var shaded = Pans.empty
        for y in 0..<Pans.side {
            for x in 0..<Pans.side { shaded.luma[y * Pans.side + x] = UInt8(60 + x * 2) }
        }
        #expect(shaded.structureChange(from: Pans.empty, rule: rule, radius: 4) == 0)
        #expect(Pans.withPasta.structureChange(from: Pans.empty, rule: rule, radius: 4) > 0.1)
    }
}
