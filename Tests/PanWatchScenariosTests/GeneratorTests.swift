import Foundation
import Testing
@testable import PanWatchCore
@testable import PanWatchScenarios

struct GeneratorTests {
    private func frames(_ run: Run, limit: Int = .max) -> [SyntheticFrame] {
        Array(ScenarioFrames(run: run).prefix(limit))
    }

    @Test func patchesMatchTheAppsSizeForTheBox() {
        let size = PanPatch.size(for: CounterView.region, frameWidth: 1280, frameHeight: 720)
        for vessel in [Vessel.stockPot, .skillet] {
            let view = CounterView(vessel: vessel)
            #expect(view.width == size.width && view.height == size.height)
            #expect(view.rimRow > 0 && view.rimRow < view.height)
        }
        let run = Run(kind: .bagPour, environment: .ledSteel, step: .pasta)
        let all = frames(run)
        #expect(all.count == Int((run.duration * 15).rounded()))
        #expect(all.allSatisfy { $0.patch.width == size.width && $0.patch.height == size.height })
    }

    @Test func theSameRunRendersTheSameFrames() {
        let run = Run(kind: .handful, environment: .dimGranite, step: .pasta)
        let first = frames(run), second = frames(run)
        #expect(first.map(\.patch) == second.map(\.patch))
        #expect(first.map { $0.vision.map(\.orderedJoints.count) } == second.map { $0.vision.map(\.orderedJoints.count) })
        let elsewhere = frames(Run(kind: .handful, environment: .brightWood, step: .pasta))
        #expect(first.map(\.patch) != elsewhere.map(\.patch))
    }

    @Test func seededRandomRepeatsAndDiffersBySeed() {
        var a = SeededRandom(name: "pot"), b = SeededRandom(name: "pot"), c = SeededRandom(name: "pan")
        let first = (0..<5).map { _ in a.next() }
        #expect(first == (0..<5).map { _ in b.next() })
        #expect(first != (0..<5).map { _ in c.next() })
    }

    @Test func dimLightIsDarkerAndLedBandsRoll() {
        func mean(_ patch: PanPatch) -> Double { Double(patch.luma.map(Int.init).reduce(0, +)) / Double(patch.pixelCount) }
        let dim = frames(Run(kind: .steamOnly, environment: .dimGranite, step: .pasta), limit: 3)[0].patch
        let bright = frames(Run(kind: .steamOnly, environment: .brightWood, step: .pasta), limit: 3)[0].patch
        #expect(mean(dim) < mean(bright) - 30)
        let led = frames(Run(kind: .steamOnly, environment: .ledSteel, step: .pasta), limit: 4)
        let row = { (patch: PanPatch, r: Int) in patch.luma[(r * patch.width)..<((r + 1) * patch.width)].map(Int.init).reduce(0, +) }
        #expect(row(led[0].patch, 30) != row(led[3].patch, 30))
    }

    @Test func aGrippingHandHidesItsOpennessAndAnOpenHandShowsIt() {
        var random = SeededRandom(name: "hands")
        let base = HandKey(t: 0, x: 0, y: 0, openness: 1, grip: .grip, joints: 8, confidence: 0.85)
        let grip = HandTrack(keys: [HandKey(t: 0, x: 0.5, y: 0.33), HandKey(t: 1, x: 0.5, y: 0.33)], base: base)
        var open = grip
        open.keys = open.keys.map { var key = $0; key.grip = .open; key.joints = 19; key.openness = 1.8; return key }
        let settings = DetectorSettings()
        var gripOpenness: [Double?] = [], openOpenness: [Double] = []
        for frame in 0..<15 {
            let t = Double(frame) / 15
            gripOpenness += trackedHands(grip.observe(at: t, in: .whiteSteel, random: &random).map { [$0] } ?? [], settings: settings)
                .map(\.openness)
            openOpenness += trackedHands(open.observe(at: t, in: .whiteSteel, random: &random).map { [$0] } ?? [], settings: settings)
                .compactMap(\.openness)
        }
        #expect(!gripOpenness.isEmpty && gripOpenness.allSatisfy { $0 == nil })
        #expect(openOpenness.count >= 10 && openOpenness.allSatisfy { $0 > 1.3 })
    }

    @Test func theSuiteCoversAddsAndNonAddsWithUniqueNames() {
        let suite = Run.suite()
        #expect(suite.count >= 40)
        #expect(Set(suite.map(\.name)).count == suite.count)
        #expect(Set(suite.filter(\.kind.isAdd).map(\.kind)).count == 11)
        #expect(Set(suite.filter { !$0.kind.isAdd }.map(\.kind)).count == 11)
    }
}
