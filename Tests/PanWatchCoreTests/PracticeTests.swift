import Foundation
import Testing
@testable import PanWatchCore
@testable import PanWatchSamples

/// Frames for the detector seen from a phone propped low on the counter, steam rising the whole time.
private struct SideTimeline {
    private(set) var frames: [FrameObservation] = []
    private var time = 0.0
    private var count = 0

    mutating func hold(_ seconds: Double, hand: Bool = false, patch: (Int) -> PanPatch) {
        for index in 0..<Int((seconds * 15).rounded()) {
            frames.append(FrameObservation(time: time, handInZone: hand, region: patch(index)))
            time += 1.0 / 15
            count += 1
        }
    }

    /// Steam over `base`, moving every frame.
    mutating func steam(_ seconds: Double, over base: PanPatch = SideView.pot) {
        let start = count
        hold(seconds) { SideView.steam(start + $0, over: base) }
    }
}

private func sideDecisions(_ timeline: SideTimeline, watch: AdditionWatch = Watches.pasta, settings: DetectorSettings = DetectorSettings()) -> [DetectorDecision] {
    var detector = AdditionDetector(settings: settings.applying(watch))
    detector.setArmed(true)
    return timeline.frames.compactMap { detector.process($0) }
}

@Suite("Low counter angle")
struct LowCounterAngleTests {
    /// A bag of pasta poured into the pot, the hand gripping it never counted.
    private var bagPour: SideTimeline {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.hold(2) { SideView.arm($0) }
        timeline.steam(3, over: SideView.somePasta)
        return timeline
    }

    @Test func bagPourFromALowCounterAngleIsCaughtWithoutACountedHand() {
        let decisions = sideDecisions(bagPour)
        #expect(decisions.map(\.outcome) == [.addition])
        #expect(decisions.first?.changeAlone == true)
    }

    @Test func lowCounterAngleChangeAloneOnlyCountsOnStepsWhoseIngredientStaysInSight() {
        #expect(sideDecisions(bagPour, watch: Watches.garlic).isEmpty)
        var off = DetectorSettings()
        off.countVisibleChange = false
        #expect(sideDecisions(bagPour, settings: off).isEmpty)
    }

    @Test func lightingChangeFromALowCounterAngleIsStillVetoed() {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.steam(4, over: SideView.brighter(SideView.pot))
        let outcomes = sideDecisions(timeline).map(\.outcome)
        #expect(outcomes.contains(.lightingChange))
        #expect(!outcomes.contains(.addition))
    }

    @Test func stirringFromALowCounterAngleIsStillIgnored() {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.hold(8, hand: true) { SideView.arm($0) }
        timeline.steam(4, over: SideView.foam)
        #expect(sideDecisions(timeline).map(\.outcome) == [.stirring])
    }

    @Test func steamAloneFromALowCounterAngleIsNotAnAddition() {
        var timeline = SideTimeline()
        timeline.steam(4)
        // A puff big enough to count as motion, then steam as usual.
        timeline.hold(0.2) { _ in SideView.pot.filling(x: 0..<32, y: 0..<SideView.rim, luma: 235) }
        timeline.steam(4)
        #expect(sideDecisions(timeline).isEmpty)
    }

    @Test func cookLeaningInFromALowCounterAngleIsNotAnAddition() {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.hold(4) { _ in SideView.cookLeaningIn }
        #expect(sideDecisions(timeline).isEmpty)
    }

    @Test func handVisitIsStillJudgedFirst() {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.hold(1, hand: true) { SideView.arm($0) }
        timeline.steam(5, over: SideView.somePasta)
        let decisions = sideDecisions(timeline)
        #expect(decisions.map(\.outcome) == [.addition])
        #expect(decisions.first?.changeAlone == false)
    }
}

@Suite("Hands holding something")
struct HoldingHandTests {
    private let center = NormPoint(x: 0.5, y: 0.5)

    @Test func aHandGrippingABagCountsWithoutItsWrist() {
        let gripping = Hands.reading(at: center, confidence: 0.7, joints: Hands.gripping)
        #expect(gripping.rejection(DetectorSettings()) == nil)
        #expect(gripping.tracked(DetectorSettings(), aspect: 16.0 / 9)?.joints.count == 5)
    }

    @Test func faintOrSparseHandsStillDoNotCount() {
        let settings = DetectorSettings()
        #expect(Hands.reading(at: center, confidence: 0.45, joints: Hands.open).rejection(settings) == .lowConfidence(0.45))
        #expect(Hands.reading(at: center, confidence: 0.55, joints: Hands.gripping).rejection(settings) == .noWrist)
        #expect(Hands.reading(at: center, confidence: 0.9, joints: [.wrist, .indexMCP, .thumbTip]).rejection(settings) == .fewJoints(3))
        // Faint joints don't count toward the four.
        #expect(Hands.reading(at: center, confidence: 0.7, joints: Hands.gripping, jointConfidence: 0.3).rejection(settings) == .fewJoints(0))
    }

    @Test func anOpenHandCountsAsBefore() {
        let settings = DetectorSettings()
        #expect(Hands.reading(at: center, confidence: 0.5, joints: Hands.open).rejection(settings) == nil)
        let hand = Hands.reading(at: center, confidence: 0.9, joints: Hands.open).tracked(settings, aspect: 1)
        #expect(hand?.joints.count == 21)
        #expect(hand?.openness != nil)
    }
}

@Suite("Practice recordings")
struct PracticeRecordingTests {
    @Test func theReaderGetsBackWhatThePhoneWrote() throws {
        let original = SamplePractice.recording()
        let read = try PracticeRecording(data: SamplePractice.data())
        #expect(read.notes == original.notes)
        #expect(read.tunings == original.tunings)
        #expect(read.markers == original.markers)
        #expect(read.verdicts == original.verdicts)
        #expect(read.frames.count == original.frames.count)
        for (frame, before) in zip(read.frames, original.frames) {
            #expect(frame.time == before.time)
            #expect(frame.patch == before.patch)
            #expect(frame.watch == before.watch)
            #expect(frame.armed == before.armed)
            #expect(frame.stepIndex == before.stepIndex)
            #expect(frame.hands.count == before.hands.count)
            for (hand, wrote) in zip(frame.hands, before.hands) {
                #expect(abs(hand.confidence - wrote.confidence) < 0.003)
                #expect(hand.joints.map(\.name) == wrote.joints.map(\.name))
                for (joint, original) in zip(hand.joints, wrote.joints) {
                    #expect(abs(joint.point.x - original.point.x) < 0.0001)
                    #expect(abs(joint.point.y - original.point.y) < 0.0001)
                }
            }
            if let region = frame.region, let wrote = before.region {
                #expect(abs(region.x - wrote.x) < 0.0001 && abs(region.width - wrote.width) < 0.0001)
            }
        }
    }

    @Test func aRecordingCutOffMidFrameKeepsWhatCameBefore() throws {
        let data = SamplePractice.data()
        let read = try PracticeRecording(data: data.prefix(data.count - 100))
        #expect(read.frames.count == SamplePractice.recording().frames.count - 1)
        #expect(throws: PracticeRecording.ReadError.notARecording) { try PracticeRecording(data: Data("hello".utf8)) }
    }

    @Test func picturesAreShrunkAndColorHalved() throws {
        var frame = SamplePractice.recording().frames[0]
        frame.patch = PanPatch(width: 128, height: 96, luma: 90, cb: 110, cr: 140)
        var data = PracticeRecording.header(notes: "")
        data.append(PracticeRecording.encode(frame))
        let patch = try PracticeRecording(data: data).frames[0].patch
        #expect(patch == PanPatch(width: 64, height: 48, luma: 90, cb: 110, cr: 140))
        // Brightness and both color planes at half size, plus hands and numbers.
        #expect(PracticeRecording.encode(frame).count < 64 * 48 * 2 + 200)
    }

    @Test func theReplayCatchesBothLowCounterAngleAddsAndNotTheReachPast() throws {
        let recording = try PracticeRecording(data: SamplePractice.data())
        let score = PracticeReplay.score(recording, settings: DetectorSettings())
        #expect(score == DetectionScore(truePositives: 2, falsePositives: 0, misses: 0))
        #expect(PracticeReplay.liveScore(recording) == DetectionScore(truePositives: 1, falsePositives: 0, misses: 1))
    }

    @Test func theOldRulesMissBothLowCounterAngleAdds() throws {
        var old = DetectorSettings()
        old.countVisibleChange = false
        old.holdingHandConfidence = 2
        let score = PracticeReplay.score(SamplePractice.recording(), settings: old)
        #expect(score == DetectionScore(truePositives: 0, falsePositives: 0, misses: 2))
    }

    @Test func settingsChangeByName() {
        let settings = DetectorSettings()
        #expect(PracticeReplay.setting("handConfidence", to: "0.4", in: settings)?.handConfidence == 0.4)
        #expect(PracticeReplay.setting("minimumHandJoints", to: "4", in: settings)?.minimumHandJoints == 4)
        #expect(PracticeReplay.setting("lightingVeto", to: "false", in: settings)?.lightingVeto == false)
        #expect(PracticeReplay.setting("noSuchSetting", to: "1", in: settings) == nil)
    }
}

@Suite("Why no offer")
struct NoOfferTests {
    @Test func theBagPourSaysWhyItsHandDidNotCount() {
        var old = DetectorSettings()
        old.countVisibleChange = false
        var watcher = PanWatcher(settings: old.applying(Watches.pasta))
        // Through the end of the bag pour.
        for frame in SamplePractice.recording().frames.prefix(7 * 15) {
            _ = watcher.process(time: frame.time, hands: frame.hands, aspect: 16.0 / 9, region: frame.region, patch: frame.patch, armed: true)
        }
        #expect(watcher.noOffer == .handNotCounted(.rejected(.lowConfidence(0.45))))
        #expect(watcher.noOffer?.text == "No hand counted: Vision only 45% sure it's a hand")
    }

    @Test func eachReasonReads() {
        #expect(NoOffer.visitTooShort(0.2).text == "Hand over the pan too briefly (0.2 s)")
        #expect(NoOffer.changeTooSmall(changed: 0.012, needed: 0.04).text == "Pan changed too little (1.2% of 4.0% needed)")
        #expect(NoOffer.lightingVeto(22).text == "Taken for a lighting change (brightness +22)")
        #expect(NoOffer.settling.text.hasPrefix("Still settling"))
    }

    @Test func aStirringVisitIsReportedAsTooLong() {
        var timeline = SideTimeline()
        timeline.steam(4)
        timeline.hold(8, hand: true) { SideView.arm($0) }
        timeline.steam(1)
        var detector = AdditionDetector(settings: DetectorSettings())
        detector.setArmed(true)
        for frame in timeline.frames { _ = detector.process(frame) }
        if case .visitTooLong(let dwell) = detector.lastMiss {
            #expect(dwell > 6)
        } else {
            Issue.record("expected a visit too long, got \(String(describing: detector.lastMiss))")
        }
    }
}

@Suite("Practice marker")
struct MarkCommandTests {
    @Test func thatWasItMarks() {
        for text in ["That was it", "that was it.", "okay, that was it", "um that was it", "Mark", "mark it", "mark that"] {
            #expect(VoiceCommand.parse(text) == .mark, "\(text)")
        }
    }

    @Test func otherTalkDoesNotMark() {
        for text in ["it was that", "mark the pan now and then", "that was it I think the pasta looks great"] {
            #expect(VoiceCommand.parse(text) != .mark, "\(text)")
        }
        #expect(VoiceCommand.parse("okay") == .yes)
    }
}
