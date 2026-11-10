import Foundation
import Testing
@testable import PanWatchCore

@Suite("Setup calibration")
struct SetupCalibrationTests {
    /// Repeatable noise, so a failing test fails the same way every time.
    private struct Noise {
        var state: UInt64

        mutating func uniform() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return (Double(state >> 11) + 0.5) / Double(1 << 53)
        }

        mutating func gaussian(_ sigma: Double) -> Double {
            sigma * (-2 * log(uniform())).squareRoot() * cos(2 * .pi * uniform())
        }
    }

    private static let side = 32

    /// `count` frames of a pan with some texture, at `luma` brightness with `sigma` of
    /// sensor noise. `extra` adds brightness at (frame, x, y), for bands.
    private func scene(
        frames count: Int, luma: Double, sigma: Double, seed: UInt64 = 7,
        extra: (Int, Int, Int) -> Double = { _, _, _ in 0 }
    ) -> [SetupCalibration.Frame] {
        var noise = Noise(state: seed)
        let side = Self.side
        return (0..<count).map { frame in
            var luma8 = [UInt8](), cb = [UInt8](), cr = [UInt8]()
            for y in 0..<side {
                for x in 0..<side {
                    // A rim and a darker interior: real contrast, like a pot.
                    let texture = (x - 16) * (x - 16) + (y - 16) * (y - 16) < 144 ? -luma * 0.3 : 0
                    let value = luma + texture + extra(frame, x, y) + noise.gaussian(sigma)
                    luma8.append(UInt8(max(0, min(255, value.rounded()))))
                    cb.append(UInt8(max(0, min(255, (120 + noise.gaussian(sigma / 3)).rounded()))))
                    cr.append(UInt8(max(0, min(255, (136 + noise.gaussian(sigma / 3)).rounded()))))
                }
            }
            let patch = PanPatch(width: side, height: side, luma: luma8, cb: cb, cr: cr)
            return SetupCalibration.Frame(time: Double(frame) / 15, patch: patch, hands: [])
        }
    }

    /// A hand Vision is `confidence` sure of, with `clear` joints it's sure of and the rest
    /// faint, spanning `size` of the frame.
    private func hand(confidence: Double, clear: Int, size: Double = 0.15) -> HandReading {
        let joints = HandReading.JointName.allCases.enumerated().map { index, name in
            HandReading.Joint(
                name: name,
                point: NormPoint(x: 0.4 + size * Double(index % 5) / 4, y: 0.3 + size * Double(index / 5) / 4),
                confidence: index < clear ? 0.8 : 0.1
            )
        }
        return HandReading(confidence: confidence, joints: joints)
    }

    private func handFrames(_ reading: HandReading?, count: Int = 45) -> [SetupCalibration.Frame] {
        (0..<count).map { SetupCalibration.Frame(time: Double($0) / 15, patch: nil, hands: reading.map { [$0] } ?? []) }
    }

    @Test func aWellLitKitchenIsReady() {
        let result = SetupCalibration.calibrate(
            still: scene(frames: 30, luma: 120, sigma: 2),
            hand: handFrames(hand(confidence: 0.9, clear: 21)),
            base: DetectorSettings()
        )
        #expect(result.findings.isEmpty)
        #expect(result.ready)
        #expect(result.spoken == "Ready.")
        // A clean picture and a clear hand leave the tuned settings alone.
        #expect(result.tuning == SetupTuning(DetectorSettings()))
    }

    @Test func aStillNoisySceneGetsThresholdsAboveItsNoise() {
        let base = DetectorSettings()
        let frames = scene(frames: 30, luma: 120, sigma: 9)
        let result = SetupCalibration.calibrate(still: frames, hand: handFrames(hand(confidence: 0.9, clear: 21)), base: base)
        let tuned = result.tuning.applied(to: base)

        #expect(result.measurements.lumaNoise > 5)
        #expect(tuned.lumaThreshold > base.lumaThreshold)
        #expect(tuned.lumaThreshold >= result.measurements.lumaNoise * 4)
        #expect(tuned.chromaThreshold >= base.chromaThreshold)

        // Fresh noise from the same scene reads as still, and nothing reads as an addition.
        let fresh = scene(frames: 30, luma: 120, sigma: 9, seed: 99).compactMap(\.patch)
        for index in 1..<fresh.count {
            let step = fresh[index].changedFraction(from: fresh[index - 1], rule: tuned.changeRule)
            #expect(step < tuned.stillnessThreshold)
            let span = fresh[index].changedFraction(from: fresh[0], rule: tuned.changeRule)
            #expect(span < tuned.additionThreshold)
        }
        // At the untuned thresholds the same noise would not read as still.
        let untuned = (1..<fresh.count).map { fresh[$0].changedFraction(from: fresh[$0 - 1], rule: base.changeRule) }
        #expect(untuned.max()! > base.stillnessThreshold)
    }

    @Test func rollingBandsAreFound() {
        let hand = handFrames(hand(confidence: 0.9, clear: 21))
        // LED bands six rows apart, rolling two thirds of a band each analyzed frame, as
        // 100 Hz light does at 15 analyses a second.
        let rows = scene(frames: 30, luma: 120, sigma: 3) { frame, _, y in
            6 * sin(2 * .pi * (Double(y) / 6 + Double(frame) * 2 / 3))
        }
        let columns = scene(frames: 30, luma: 120, sigma: 3) { frame, x, _ in
            6 * sin(2 * .pi * (Double(x) / 6 + Double(frame) * 2 / 3))
        }
        let steady = scene(frames: 30, luma: 120, sigma: 3)

        let banded = SetupCalibration.calibrate(still: rows, hand: hand, base: DetectorSettings())
        #expect(banded.findings.contains(.flicker))
        #expect(banded.measurements.flicker > SetupCalibration.flickerLimit)
        // Flicker is handled by the camera, so on its own it doesn't stop the check.
        #expect(banded.ready)
        #expect(SetupCalibration.calibrate(still: columns, hand: hand, base: DetectorSettings()).findings.contains(.flicker))
        // Noise alone isn't flicker.
        let calm = SetupCalibration.calibrate(still: steady, hand: hand, base: DetectorSettings())
        #expect(!calm.findings.contains(.flicker))
        #expect(calm.measurements.flicker < SetupCalibration.flickerLimit / 2)
    }

    @Test func aWholeBoxBeatIsFound() {
        let beating = scene(frames: 30, luma: 120, sigma: 2) { frame, _, _ in frame % 2 == 0 ? 5 : -5 }
        let result = SetupCalibration.calibrate(still: beating, hand: handFrames(hand(confidence: 0.9, clear: 21)), base: DetectorSettings())
        #expect(result.findings.contains(.flicker))
    }

    @Test func aWeakPartlyHiddenHandLowersTheMinimumsButNotPastTheFloor() {
        let base = DetectorSettings()
        let still = scene(frames: 30, luma: 120, sigma: 2)

        // Somewhat weak: 70% of what was measured.
        let weak = SetupCalibration.calibrate(still: still, hand: handFrames(hand(confidence: 0.55, clear: 8)), base: base)
        #expect(abs(weak.tuning.handConfidence - 0.385) < 1e-9)
        #expect(weak.tuning.minimumHandJoints == 5)
        #expect(weak.tuning.holdingHandConfidence >= weak.tuning.handConfidence)
        #expect(!weak.findings.contains(.handNotSeen))

        // Barely there, fingers hidden: down to the floors and no further.
        let faint = SetupCalibration.calibrate(still: still, hand: handFrames(hand(confidence: 0.32, clear: 4)), base: base)
        #expect(faint.tuning.handConfidence == SetupCalibration.confidenceFloor)
        #expect(faint.tuning.minimumHandJoints == SetupCalibration.jointFloor)
        #expect(faint.tuning.holdingHandJoints >= SetupCalibration.jointFloor)
        let tuned = faint.tuning.applied(to: base)
        #expect(tuned.handConfidence < base.handConfidence)
        #expect(tuned.minimumHandJoints < base.minimumHandJoints)
        #expect(hand(confidence: 0.32, clear: 4).rejection(tuned) == nil)

        // Under the floor it isn't a usable hand at all.
        let none = SetupCalibration.calibrate(still: still, hand: handFrames(hand(confidence: 0.2, clear: 3)), base: base)
        #expect(none.fix == .handNotSeen)
        #expect(none.spoken.hasPrefix("Can't see your hand."))
        #expect(none.tuning.handConfidence == base.handConfidence)
    }

    @Test func aLookalikeRaisesTheHandMinimumOnlyBelowTheRealHand() {
        let base = DetectorSettings()
        var still = scene(frames: 30, luma: 120, sigma: 2)
        for index in still.indices { still[index].hands = [hand(confidence: 0.6, clear: 8)] }
        let raised = SetupCalibration.calibrate(still: still, hand: handFrames(hand(confidence: 0.95, clear: 21)), base: base)
        #expect(abs(raised.tuning.handConfidence - 0.65) < 1e-9)
        #expect(raised.findings.contains(.lookalike))
        #expect(hand(confidence: 0.6, clear: 8).rejection(raised.tuning.applied(to: base)) != nil)

        // A real hand no surer than the lookalike leaves the minimum where the hand puts it.
        let close = SetupCalibration.calibrate(still: still, hand: handFrames(hand(confidence: 0.7, clear: 21)), base: base)
        #expect(abs(close.tuning.handConfidence - 0.49) < 1e-9)
    }

    @Test func aDarkSceneSaysTooDark() {
        let result = SetupCalibration.calibrate(
            still: scene(frames: 30, luma: 26, sigma: 4),
            hand: handFrames(hand(confidence: 0.9, clear: 21)),
            base: DetectorSettings()
        )
        #expect(result.findings.contains(.tooDark))
        #expect(result.fix == .tooDark)
        #expect(result.spoken == "It's dark. Turn on a light near the stove.")
        #expect(!result.ready)
    }

    @Test func noPictureIsSaid() {
        let result = SetupCalibration.calibrate(still: handFrames(nil, count: 30), hand: handFrames(nil), base: DetectorSettings())
        #expect(result.fix == .noPicture)
    }

    @Test func exposureMatchesTheMains() {
        // 1/200 s at ISO 100 under 60 Hz mains: one 1/120 s pulse, ISO lowered to match.
        let sixty = MainsPower.exposure(current: 1.0 / 200, iso: 100, hertz: 60, shortest: 1e-5, longest: 1.0 / 30, minISO: 20, maxISO: 2000)
        #expect(abs(sixty!.duration - 1.0 / 120) < 1e-12)
        #expect(abs(sixty!.iso - 60) < 1e-9)
        // A dim kitchen at 1/36 s rounds to three 1/100 s pulses, within a 1/30 s frame.
        let fifty = MainsPower.exposure(current: 1.0 / 36, iso: 800, hertz: 50, shortest: 1e-5, longest: 1.0 / 30, minISO: 20, maxISO: 2000)
        #expect(abs(fifty!.duration - 3.0 / 100) < 1e-12)
        // Bright sun can't take 1/120 s without blowing out the pan: leave it to the plain lock.
        #expect(MainsPower.exposure(current: 1.0 / 2000, iso: 30, hertz: 60, shortest: 1e-5, longest: 1.0 / 30, minISO: 25, maxISO: 2000) == nil)
        #expect(MainsPower.hertz(region: "US") == 60)
        #expect(MainsPower.hertz(region: "DE") == 50)
        #expect(MainsPower.other(60) == 50)
    }
}

@Suite("Setup check by voice")
struct SetupCheckVoiceTests {
    @Test func checkTheSetupIsHeard() {
        #expect(VoiceCommand.parse("check the setup") == .checkSetup)
        #expect(VoiceCommand.parse("Check the set up again, please") == .checkSetup)
        #expect(VoiceCommand.parse("skip") == .skip)
        #expect(VoiceCommand.parse("skip it") == .skip)
    }
}
