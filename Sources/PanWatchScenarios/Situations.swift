import Foundation
@testable import PanWatchCore

/// The recipe step whose watch is in force.
enum StepWatch: String, Sendable {
    case pasta, garlic

    /// The step's watch, taken from the Garlic Butter Pasta recipe itself.
    var watch: AdditionWatch {
        Recipe.garlicButterPasta.steps.compactMap(\.watch).first { $0.ingredient == rawValue }!
    }

    /// The detector settings during the step, built the way `CookSession.effectiveSettings` builds them.
    var settings: DetectorSettings {
        var effective = DetectorSettings()
        if let minimum = watch.minimumChange {
            effective.additionThreshold = min(effective.additionThreshold, minimum)
        }
        effective.countRelease = effective.countRelease && watch.countsRelease
        return effective
    }
}

/// What happens at the stove.
enum Kind: String, CaseIterable, Sendable {
    case bagPour = "bag pour"
    case boxPour = "box pour"
    case handful
    case tongs
    case spoon
    case cup
    case boardScrape = "board scrape"
    case slowPour = "slow pour"
    case fastToss = "fast toss"
    case addThenStir = "add then stir"
    case garlicPinch = "garlic pinch"
    case stir = "stirring"
    case lidOn = "lid on"
    case lidOff = "lid off"
    case movePot = "moving the pot"
    case taste = "tasting"
    case reachPast = "reaching past"
    case walkBehind = "walking behind"
    case lightOn = "light on"
    case steamOnly = "steam only"
    case phantomStill = "still phantom"
    case phantomFlicker = "flickering phantom"

    var isAdd: Bool {
        switch self {
        case .bagPour, .boxPour, .handful, .tongs, .spoon, .cup, .boardScrape, .slowPour, .fastToss, .addThenStir, .garlicPinch: true
        default: false
        }
    }

    /// Seconds after the food starts going in by which the offer must come.
    var window: Double {
        switch self {
        case .slowPour: 12
        case .addThenStir: 14
        default: 8
        }
    }
}

/// One situation in one environment, under one step's settings.
struct Run: Sendable {
    let kind: Kind
    let environment: Environment
    let step: StepWatch

    /// When the event starts, give or take a little; the detector has armed and warmed up by then.
    static let eventTime = 6.0

    var name: String { "\(kind.rawValue), \(environment.name)" }
    /// Garlic-step work happens in a skillet. Rice goes into a pot of water, and its watch is
    /// the same as garlic's (a hand visit is enough), so the cup uses the garlic settings.
    var vessel: Vessel { step == .pasta || kind == .cup ? .stockPot : .skillet }
    var duration: Double { Self.eventTime + kind.window + 4 }

    static func suite() -> [Run] {
        let wood = Environment.brightWood, granite = Environment.dimGranite
        let led = Environment.ledSteel, white = Environment.whiteSteel
        let plan: [(Kind, [(Environment, StepWatch)])] = [
            (.bagPour, [(wood, .pasta), (granite, .pasta), (led, .pasta)]),
            (.boxPour, [(led, .pasta), (white, .pasta)]),
            (.handful, [(wood, .pasta), (granite, .pasta), (led, .pasta)]),
            (.tongs, [(granite, .pasta), (white, .pasta)]),
            (.spoon, [(wood, .garlic), (led, .garlic)]),
            (.cup, [(granite, .garlic), (led, .garlic)]),
            (.boardScrape, [(wood, .garlic), (white, .garlic)]),
            (.slowPour, [(granite, .pasta), (led, .pasta)]),
            (.fastToss, [(wood, .pasta), (led, .pasta)]),
            (.addThenStir, [(granite, .pasta), (white, .pasta)]),
            (.garlicPinch, [(wood, .garlic), (granite, .garlic), (led, .garlic)]),
            (.stir, [(wood, .pasta), (granite, .garlic), (led, .pasta)]),
            (.lidOn, [(led, .pasta), (granite, .pasta)]),
            (.lidOff, [(wood, .pasta), (white, .pasta)]),
            (.movePot, [(granite, .pasta), (led, .garlic)]),
            (.taste, [(wood, .garlic), (white, .pasta)]),
            (.reachPast, [(led, .garlic), (wood, .pasta)]),
            (.walkBehind, [(granite, .pasta), (white, .pasta)]),
            (.lightOn, [(wood, .pasta), (granite, .pasta)]),
            (.steamOnly, [(led, .pasta), (white, .pasta)]),
            (.phantomStill, [(wood, .garlic), (granite, .pasta)]),
            (.phantomFlicker, [(wood, .pasta), (granite, .garlic)]),
        ]
        return plan.flatMap { kind, places in places.map { Run(kind: kind, environment: $0.0, step: $0.1) } }
    }
}

/// The hands and the scene of one run over time.
struct Script {
    var eventTime: Double
    var hands: [HandTrack]
    var scene: (Double) -> SceneState
}

extension Run {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func script() -> Script {
        var random = SeededRandom(name: name + "/script")
        let view = CounterView(vessel: vessel)
        let t0 = Self.eventTime + random.range(-0.15, 0.15)
        let rimY = view.rimY
        // Where a hand pours from: over the middle of the pot, about 13 cm above the rim.
        let over = NormPoint(x: 0.50 + random.range(-0.03, 0.03), y: rimY - 0.21)
        // The cook's hand comes in from above, out of frame.
        let out = NormPoint(x: 0.84, y: -0.04)
        let sleeves = [
            Color3(y: 60, cb: 145, cr: 118), Color3(y: 120, cb: 128, cr: 128), Color3(y: 90, cb: 110, cr: 175),
            Color3(y: 215, cb: 128, cr: 128), Color3(y: 35, cb: 128, cr: 128),
        ]
        let sleeve = sleeves[Int(random.range(0, 4.999))]
        let size = random.range(0.26, 0.30)
        let foreshortening = random.range(0.55, 0.85)
        let steam = vessel == .stockPot ? 0.5 : 0.15
        let boil = vessel == .stockPot ? 0.6 : 0.35
        let end = duration - t0 + 1

        func k(
            _ t: Double, _ p: NormPoint, dx: Double = 0, dy: Double = 0,
            open: Double? = nil, grip: Grip? = nil, joints: Int? = nil, conf: Double? = nil
        ) -> HandKey {
            HandKey(t: t0 + t, x: p.x + dx, y: p.y + dy, openness: open, grip: grip, joints: joints, confidence: conf)
        }
        func hand(
            _ keys: [HandKey], _ grip: Grip, joints: Int, confidence: Double, openness: Double = 1,
            prop: Prop = .none, source: HandTrack.Source = .cook
        ) -> HandTrack {
            let base = HandKey(t: 0, x: 0, y: 0, openness: openness, grip: grip, joints: joints, confidence: confidence)
            var track = HandTrack(source, keys: keys, base: base)
            track.prop = prop
            track.size = size
            track.foreshortening = foreshortening
            track.sleeve = sleeve
            return track
        }
        /// Stirring circles over the pot from `start` to `stop`.
        func circles(_ start: Double, _ stop: Double) -> [HandKey] {
            stride(from: start, through: stop, by: 0.1).map { t in
                let a = 2 * Double.pi * (t - start) / 1.2
                return k(t, over, dx: 0.06 * cos(a), dy: -0.02 + 0.02 * sin(a))
            }
        }
        /// The cook stands at the stove, leans in while working over the pot, and settles back
        /// after: as close as before, or nearer or farther.
        let stance = random.range(0.2, 0.7)
        func lean(_ t: Double, _ start: Double, _ stop: Double, linger: Double? = nil) -> Double {
            let standing = 0.5, after = max(linger ?? 0, stance)
            if t < t0 + stop { return standing + (1 - standing) * ramp(t, t0 + start - 0.6, t0 + start) }
            return after + (1 - after) * (1 - ramp(t, t0 + stop, t0 + stop + 1))
        }
        /// Adding a lot of cold food knocks the boil back for a while.
        func boilDrop(_ t: Double, _ depth: Double, from start: Double) -> Double {
            1 - depth * ramp(t, t0 + start, t0 + start + 2)
        }

        var hands: [HandTrack] = []
        var scene: (Double) -> SceneState = { _ in SceneState(steam: steam, boil: boil) }

        switch kind {
        case .bagPour:
            hands = [hand([
                k(-0.7, out), k(-0.1, over, dx: 0.02, dy: -0.02), k(0.3, over), k(0.8, over, dx: -0.02, dy: 0.01),
                k(1.2, over, dx: 0.01), k(1.6, over, dx: -0.01, dy: 0.01), k(2.2, out),
            ], .grip, joints: 8, confidence: 0.78, prop: .bag)]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.6, from: 1), boil: boil * boilDrop(t, 0.6, from: 1))
                s.spaghetti = ramp(t, t0 + 0.2, t0 + 1.4)
                s.splash = 0.6 * pulse(t, t0 + 0.2, t0 + 1.2)
                s.cookNear = lean(t, -0.3, 1.9, linger: 0.35)
                return s
            }
        case .boxPour:
            let shakes = (0..<9).map { k(Double($0) * 0.15, over, dx: $0 % 2 == 0 ? 0.025 : -0.025, dy: 0.01) }
            hands = [hand([k(-0.7, out), k(-0.1, over)] + shakes + [k(1.9, out)], .grip, joints: 8, confidence: 0.75, prop: .box)]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.6, from: 1), boil: boil * boilDrop(t, 0.6, from: 1))
                s.splash = pulse(t, t0 + 0.1, t0 + 1.3)
                s.cookNear = lean(t, -0.3, 1.5)
                return s
            }
        case .handful:
            hands = [hand([
                k(-0.6, out), k(-0.1, over, dy: 0.01), k(0.5, over, dy: 0.02),
                k(0.75, over, dy: 0.02, open: 1.8, grip: .open, joints: 17), k(1.2, over), k(1.7, out, open: 1.6),
            ], .grip, joints: 11, confidence: 0.8)]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.3, from: 0.8), boil: boil * boilDrop(t, 0.3, from: 0.8))
                s.splash = 0.4 * pulse(t, t0 + 0.7, t0 + 1.0)
                s.cookNear = lean(t, -0.3, 1.3)
                return s
            }
        case .tongs:
            hands = [hand([
                k(-0.6, out), k(-0.1, over, dx: -0.03, dy: -0.06), k(0.4, over, dx: -0.03, dy: -0.02),
                k(0.8, over, dx: -0.03, dy: -0.07), k(1.4, over, dx: 0.03, dy: -0.02), k(1.9, over, dx: 0.03, dy: -0.07),
                k(2.4, out),
            ], .partial, joints: 6, confidence: 0.68, prop: .tongs)]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.2, from: 0.5), boil: boil * boilDrop(t, 0.2, from: 0.5))
                s.splash = 0.3 * (pulse(t, t0 + 0.4, t0 + 0.6) + pulse(t, t0 + 1.4, t0 + 1.6))
                s.cookNear = lean(t, -0.3, 2.1)
                return s
            }
        case .spoon:
            hands = [hand([
                k(-0.6, out), k(-0.1, over), k(0.3, over, dy: 0.03), k(0.5, over), k(0.7, over, dy: 0.03), k(1.0, over),
                k(1.5, out),
            ], .partial, joints: 8, confidence: 0.72, prop: .spoon)]
            scene = { t in
                var s = SceneState(steam: steam + 0.25 * pulse(t, t0 + 0.4, t0 + 4), boil: boil)
                s.cookNear = lean(t, -0.3, 1.2)
                return s
            }
        case .cup:
            hands = [hand([
                k(-0.7, out), k(-0.1, over, dx: 0.03), k(0.4, over, dy: 0.01), k(1.0, over, dx: -0.03, dy: 0.02),
                k(1.4, over, dx: -0.03, dy: 0.02), k(2.0, out),
            ], .grip, joints: 8, confidence: 0.76, prop: .cup)]
            scene = { t in
                var s = SceneState(steam: steam + 0.4 * pulse(t, t0 + 0.3, t0 + 2.5), boil: boil * boilDrop(t, 0.3, from: 1))
                s.splash = 0.5 * pulse(t, t0 + 0.3, t0 + 1.2)
                s.cookNear = lean(t, -0.3, 1.6)
                return s
            }
        case .boardScrape:
            let boardAt = NormPoint(x: 0.68, y: rimY - 0.17)
            var board = hand([
                k(-0.7, NormPoint(x: 0.88, y: 0.02)), k(-0.1, boardAt), k(2.8, boardAt, dx: 0.005), k(3.4, NormPoint(x: 0.9, y: -0.02)),
            ], .grip, joints: 7, confidence: 0.7, prop: .board)
            board.shoulder = NormPoint(x: 0.95, y: -0.2)
            let scrapes = (0..<8).map { k(0.3 * Double($0), over, dx: $0 % 2 == 0 ? 0.05 : -0.05, dy: -0.03) }
            let knife = hand([k(-0.4, out)] + scrapes + [k(3.0, out)], .partial, joints: 6, confidence: 0.65, prop: .knife)
            hands = [board, knife]
            scene = { t in
                var s = SceneState(steam: steam + 0.5 * pulse(t, t0 + 0.6, t0 + 5), boil: boil)
                s.cookNear = lean(t, -0.3, 3.0)
                return s
            }
        case .slowPour:
            let drift = (0..<10).map { k(0.5 * Double($0), over, dx: 0.015 * sin(Double($0)), dy: -0.01) }
            hands = [hand([k(-0.7, out), k(-0.1, over, dy: -0.02)] + drift + [k(5.2, out)], .grip, joints: 8, confidence: 0.77, prop: .bag)]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.6, from: 2), boil: boil * boilDrop(t, 0.6, from: 2))
                s.spaghetti = ramp(t, t0 + 0.3, t0 + 4.8)
                s.splash = 0.3 * pulse(t, t0 + 0.3, t0 + 4.6)
                s.cookNear = lean(t, -0.3, 4.9, linger: 0.35)
                return s
            }
        case .fastToss:
            var toss = hand([
                k(-0.35, NormPoint(x: 0.86, y: 0.08)), k(0, NormPoint(x: 0.58, y: rimY - 0.26)),
                k(0.12, NormPoint(x: 0.50, y: rimY - 0.23), open: 1.7, grip: .open, joints: 15),
                k(0.3, NormPoint(x: 0.40, y: rimY - 0.28)), k(0.55, NormPoint(x: 0.12, y: -0.02)),
            ], .grip, joints: 10, confidence: 0.7)
            toss.extraDropout = 0.1
            hands = [toss]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.3, from: 0.3), boil: boil * boilDrop(t, 0.3, from: 0.3))
                s.splash = 0.6 * pulse(t, t0 + 0.15, t0 + 0.5)
                s.cookNear = lean(t, -0.3, 0.4)
                return s
            }
        case .addThenStir:
            let pour = hand([
                k(-0.7, out), k(-0.1, over), k(0.4, over, dx: 0.02), k(1.0, over, dx: -0.02), k(1.8, over, dy: -0.02),
            ], .grip, joints: 8, confidence: 0.78, prop: .bag)
            let stir = hand(circles(1.9, 9.5) + [k(10, out)], .partial, joints: 8, confidence: 0.72, prop: .spoon)
            hands = [pour, stir]
            scene = { t in
                var s = SceneState(steam: steam * boilDrop(t, 0.6, from: 1), boil: boil * boilDrop(t, 0.6, from: 1))
                // Stirring pushes the strands under.
                s.spaghetti = ramp(t, t0 + 0.2, t0 + 1.4) * (1 - 0.85 * ramp(t, t0 + 2, t0 + 6))
                s.splash = 0.2 * pulse(t, t0 + 2, t0 + 9.5)
                s.cookNear = lean(t, -0.3, 9.7, linger: 0.35)
                return s
            }
        case .garlicPinch:
            hands = [hand([
                k(-0.6, out), k(-0.1, over, dy: 0.02), k(0.2, over, dy: 0.02, open: 1.3), k(0.4, over, dy: 0.02, open: 1.1),
                k(0.6, over, dy: 0.02, open: 1.35), k(0.9, over, dy: 0.02, open: 1.15), k(1.4, out),
            ], .pinch, joints: 13, confidence: 0.74, openness: 1.1)]
            scene = { t in
                var s = SceneState(steam: steam + 0.15 * pulse(t, t0 + 0.3, t0 + 3), boil: boil)
                s.cookNear = lean(t, -0.3, 1.1)
                return s
            }
        case .stir:
            hands = [hand([k(-0.6, out)] + circles(0, 10) + [k(10.5, out)], .partial, joints: 8, confidence: 0.72, prop: .spoon)]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.splash = 0.15 * pulse(t, t0, t0 + 10)
                s.cookNear = lean(t, -0.3, 10.2)
                return s
            }
        case .lidOn:
            var lid = hand([
                k(-0.8, NormPoint(x: 0.86, y: -0.02)), k(-0.1, over, dy: -0.12), k(0.6, NormPoint(x: over.x, y: rimY - 0.14)),
                k(0.9, NormPoint(x: over.x, y: rimY - 0.10)), k(1.3, out),
            ], .grip, joints: 7, confidence: 0.74, prop: .lid)
            lid.propWindow = (t0 - 1)...(t0 + 0.9)
            hands = [lid]
            scene = { t in
                let on = ramp(t, t0 + 0.85, t0 + 1.0)
                var s = SceneState(steam: steam * (1 - on) + 0.04 * on, boil: boil * (1 - on) + 0.05 * on)
                s.lidSeated = t >= t0 + 0.9
                s.cookNear = lean(t, -0.3, 1.1)
                return s
            }
        case .lidOff:
            var lid = hand([
                k(-0.7, out), k(0, NormPoint(x: over.x, y: rimY - 0.10)), k(0.5, NormPoint(x: over.x, y: rimY - 0.10)),
                k(1.0, NormPoint(x: over.x + 0.06, y: rimY - 0.22)), k(1.6, out),
            ], .grip, joints: 7, confidence: 0.74, prop: .lid)
            lid.propWindow = (t0 + 0.5)...(t0 + 2)
            hands = [lid]
            scene = { t in
                let off = t >= t0 + 0.5
                var s = SceneState(
                    steam: off ? 0.6 + 0.4 * (1 - ramp(t, t0 + 0.5, t0 + 3.5)) : 0.04,
                    boil: off ? boil : 0.05
                )
                s.lidSeated = !off
                s.cookNear = lean(t, -0.3, 1.3)
                return s
            }
        case .movePot where vessel == .stockPot:
            // Both hands on the side handles, sliding the pot about 2 cm.
            let slide = 3 * CounterView.region.width / Double(view.width)
            func side(_ x: Double, from start: NormPoint, shoulder: NormPoint) -> HandTrack {
                let grab = NormPoint(x: x, y: rimY + 0.0)
                var track = hand([
                    k(-0.7, start), k(0, grab), k(0.5, grab), k(1.2, grab, dx: slide), k(1.6, grab, dx: slide), k(2.2, start),
                ], .grip, joints: 8, confidence: 0.72)
                track.shoulder = shoulder
                return track
            }
            hands = [
                side(0.3625, from: NormPoint(x: 0.2, y: -0.02), shoulder: NormPoint(x: 0.15, y: -0.3)),
                side(0.6375, from: NormPoint(x: 0.8, y: -0.02), shoulder: NormPoint(x: 0.88, y: -0.35)),
            ]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.potShift = 3 * ramp(t, t0 + 0.5, t0 + 1.2)
                s.splash = 0.3 * pulse(t, t0 + 0.5, t0 + 1.2)
                s.cookNear = lean(t, -0.3, 1.8)
                return s
            }
        case .movePot:
            // One hand on the skillet's long handle, shaking the pan.
            let grab = NormPoint(x: 0.67, y: rimY - 0.03)
            let shakes = (0..<13).map { k(0.12 * Double($0), grab, dx: $0 % 2 == 0 ? 0.0125 : -0.0125) }
            var shake = hand([k(-0.7, NormPoint(x: 0.9, y: 0))] + shakes + [k(2.1, NormPoint(x: 0.92, y: 0))], .grip, joints: 8, confidence: 0.72)
            shake.shoulder = NormPoint(x: 0.95, y: -0.2)
            hands = [shake]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.potShift = 2 * sin(2 * .pi * (t - t0) / 0.24) * pulse(t, t0, t0 + 1.5)
                s.splash = 0.4 * pulse(t, t0, t0 + 1.5)
                s.cookNear = lean(t, -0.3, 1.8)
                return s
            }
        case .taste:
            hands = [hand([
                k(-0.6, out), k(-0.1, over, dy: -0.05), k(0.4, over), k(0.8, over, dy: -0.06), k(1.3, NormPoint(x: 0.75, y: -0.04)),
            ], .partial, joints: 8, confidence: 0.72, prop: .spoon)]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.cookNear = lean(t, -0.3, 1.0)
                return s
            }
        case .reachPast:
            // Over the top of the pot to the back burner, and back with a pan a few seconds later.
            var there = hand([
                k(-0.4, NormPoint(x: 0.95, y: 0.20)), k(0.3, NormPoint(x: 0.50, y: 0.23)), k(0.8, NormPoint(x: 0.02, y: 0.18)),
            ], .open, joints: 15, confidence: 0.74)
            var back = hand([
                k(3.5, NormPoint(x: 0.02, y: 0.18)), k(4.0, NormPoint(x: 0.50, y: 0.24)), k(4.5, NormPoint(x: 0.95, y: 0.20)),
            ], .grip, joints: 9, confidence: 0.74)
            for index in [0, 1] {
                var track = index == 0 ? there : back
                track.shoulder = NormPoint(x: 0.95, y: -0.1)
                track.extraDropout = 0.08
                if index == 0 { there = track } else { back = track }
            }
            hands = [there, back]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.cookNear = max(lean(t, -0.4, 0.8), lean(t, 3.5, 4.5))
                return s
            }
        case .walkBehind:
            var swing = hand([k(0.5, NormPoint(x: 0.32, y: rimY - 0.08)), k(1.0, NormPoint(x: 0.58, y: rimY - 0.06))],
                             .open, joints: 8, confidence: 0.5, source: .passerby)
            swing.size = 0.12
            hands = [swing]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                if t >= t0, t <= t0 + 1.8 { s.walkerColumn = -10 + 84 * (t - t0) / 1.8 }
                return s
            }
        case .lightOn:
            // Reaching up past the pot to the range-hood switch.
            var reach = hand([
                k(-0.6, NormPoint(x: 0.92, y: 0.75)), k(-0.1, NormPoint(x: 0.66, y: 0.14)), k(0.6, NormPoint(x: 0.64, y: 0.13)),
                k(1.1, NormPoint(x: 0.92, y: 0.75)),
            ], .open, joints: 12, confidence: 0.72)
            reach.shoulder = NormPoint(x: 0.98, y: 0.95)
            hands = [reach]
            scene = { t in
                var s = SceneState(steam: steam, boil: boil)
                s.hoodLight = ramp(t, t0 + 0.3, t0 + 0.45)
                s.cookNear = lean(t, -0.3, 0.9)
                return s
            }
        case .steamOnly:
            let p1 = random.range(0, 6.28), p2 = random.range(0, 6.28)
            scene = { t in
                let gust = max(0, sin(t * 1.3 + p1)) * max(0, sin(t * 0.37 + p2))
                return SceneState(steam: min(1, 0.45 + 0.3 * ramp(t, 0, 10) + 0.5 * gust), boil: 0.9)
            }
        case .phantomStill, .phantomFlicker:
            let still = kind == .phantomStill
            let spot = still ? NormPoint(x: 0.27, y: 0.70) : NormPoint(x: 0.40 + random.range(-0.03, 0.03), y: 0.30)
            var phantom = hand([k(0, spot), k(end, spot)], .open, joints: 7, confidence: 0.56, source: .phantom)
            phantom.size = 0.12
            phantom.presence = still ? 0.92 : 0.3
            phantom.jitter = still ? 0.003 : 0.012
            phantom.shoulder = NormPoint(x: spot.x + random.range(-0.2, 0.2), y: spot.y - 0.3)
            hands = [phantom]
        }
        return Script(eventTime: t0, hands: hands, scene: scene)
    }
}
