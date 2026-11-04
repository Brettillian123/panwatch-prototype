import Foundation
@testable import PanWatchCore

// A second, independent set of situations, kept apart from the suite the detector is tuned
// on: other pots, cameras, lights, counters, hands, ingredients and things that aren't adds.
// The same generator also samples situations at random for a stress run.

/// What a step adds, the pot it goes in, and the ways a cook puts it in.
enum Food: String, CaseIterable, Sendable {
    case spaghetti, penne, rice, eggs, broccoli, chicken, garlic

    /// The recipe's own watch for the step.
    var watch: AdditionWatch {
        let ingredient = self == .spaghetti || self == .penne ? "pasta" : rawValue
        return Recipe.all.flatMap(\.steps).compactMap(\.watch).first { $0.ingredient == ingredient }!
    }

    var settings: DetectorSettings { DetectorSettings().applying(watch) }
    var vessel: Vessel { self == .chicken || self == .garlic ? .skillet : .stockPot }

    var methods: [Method] {
        switch self {
        case .spaghetti: [.pour, .handful, .toss, .slowPour, .pourThenStir]
        case .penne: [.shake, .handful, .toss, .pourThenStir]
        case .rice: [.pour, .slowPour]
        case .eggs: [.spoon, .lay]
        case .broccoli: [.handful, .toss, .tongs, .scrape]
        case .chicken: [.tongs, .lay]
        case .garlic: [.pinch, .scrape, .spoon]
        }
    }

    var color: Color3 {
        switch self {
        case .spaghetti, .penne: Color3(y: 205, cb: 98, cr: 145)
        case .rice: Color3(y: 230, cb: 122, cr: 132)
        case .eggs: Color3(y: 215, cb: 118, cr: 136)
        case .broccoli: Color3(y: 95, cb: 100, cr: 105)
        case .chicken: Color3(y: 185, cb: 112, cr: 150)
        case .garlic: Color3(y: 220, cb: 115, cr: 134)
        }
    }

    /// How far a full add knocks the boil back.
    var chill: Double {
        switch self {
        case .spaghetti, .penne: 0.6
        case .broccoli, .rice: 0.4
        case .eggs: 0.25
        case .chicken, .garlic: 0.1
        }
    }

    var pieces: Int { self == .eggs || self == .chicken ? 3 : 2 }
}

enum Method: String, Sendable {
    case pour = "poured", shake = "shaken from the box", handful = "by the handful", toss = "tossed"
    case spoon = "on a spoon", tongs = "with tongs", lay = "laid in by hand", pinch = "pinched"
    case scrape = "off a board", slowPour = "poured slowly", pourThenStir = "poured then stirred"
}

/// Things a cook does at the stove that aren't adding anything.
enum Chore: String, CaseIterable, Sendable {
    case stir = "stirring", taste = "tasting", lidOn = "lid on", lidOff = "lid off", hover = "hand hovering"
    case wipe = "wiping the stove", mitt = "oven mitt", child = "child's hand", phone = "phone lights up"
    case boilOver = "boiling over", backPot = "back pot stirred", reachPast = "reaching past", move = "moving the pot"
    case steam = "steam only"
}

enum Action: Sendable {
    case add(Food, Method)
    case chore(Chore)

    var isAdd: Bool {
        switch self {
        case .add: true
        case .chore: false
        }
    }

    var label: String {
        switch self {
        case let .add(food, method): "\(food.rawValue) \(method.rawValue)"
        case let .chore(chore): chore.rawValue
        }
    }
}

extension Lighting {
    static let afternoonSun = Lighting(gain: 1.3, noise: 1.6, chromaNoise: 1.1, cbShift: -5, crShift: 6, shadowDepth: 0.45, sunShadow: 0.35)
    static let underCabinet = Lighting(
        gain: 1.05, noise: 2.2, chromaNoise: 1.6, cbShift: 10, crShift: -8, banding: 0.09, bandPeriod: 16, bandRoll: 0.05, shadowDepth: 0.2
    )
    static let dimBulb = Lighting(gain: 0.42, noise: 5, chromaNoise: 3.5, cbShift: -16, crShift: 14, shadowDepth: 0.15, flicker: 0.03)
}

/// One situation: the step in force, what happens, and everything about the kitchen and the cook.
struct Stage {
    var name: String
    /// The step being cooked, which sets the pot and the detector's settings.
    var food: Food
    var action: Action
    /// Rim row, pot width and pot middle, as fractions of the box.
    var rim: Double
    var potWidth: Double
    var potCenter = 0.5
    var light = Lighting.underCabinet
    var surface = Surface.butcherBlock
    var finish = PotKind.steel
    var steam = 0.5
    var boil = 0.6
    var handSize = 0.28
    var skin = Color3.skin
    var sleeve = Color3(y: 60, cb: 145, cr: 118)
    var longSleeve = false
    /// 1 is the suite's pace; 2 is twice as fast.
    var speed = 1.0
    /// Where the arm comes into the frame, across the top.
    var entry = 0.84
    /// How high over the rim the hand works, in frame heights.
    var lift = 0.21
    /// How well Vision sees the hand, -1 poorly to 1 well.
    var grip = 0.0
    var walkers = 0
    /// Sampled factors and their buckets, for the stress breakdown.
    var factors: [(String, String)] = []

    init(_ name: String, _ food: Food, _ action: Action) {
        self.name = name
        self.food = food
        self.action = action
        rim = food.vessel == .stockPot ? 0.44 : 0.67
        potWidth = food.vessel == .stockPot ? 0.62 : 0.72
    }

    var vessel: Vessel { food.vessel }

    var view: CounterView {
        CounterView(
            vessel: vessel, rim: rim, left: potCenter - potWidth / 2, right: potCenter + potWidth / 2,
            floor: vessel == .skillet ? min(0.97, rim + 0.22) : 1
        )
    }

    var environment: Environment {
        let dim = max(0, 1 - light.gain)
        return Environment(
            name: name, surface: surface, pot: finish, lighting: light, dropout: 0.04 + 0.18 * dim,
            confidenceShift: 0.03 - 0.25 * dim, jointShift: dim > 0.4 ? -2 : dim > 0.2 ? -1 : 0, jointNoise: 0.003 + 0.005 * dim
        )
    }

    /// Seconds after the food starts going in by which the offer must come.
    var window: Double {
        let base: Double = switch action {
        case .add(_, .slowPour): 12
        case .add(_, .pourThenStir): 14
        case .add(.eggs, _), .add(.chicken, _): 10
        default: 8
        }
        return base * max(1, 1 / speed)
    }

    var duration: Double { 6 + window + 4 }

    var frames: ScenarioFrames { ScenarioFrames(name: name, script: script(), view: view, environment: environment, duration: duration) }
}

/// What changes in the picture, in seconds from the event (before the pace is applied).
private struct Effects {
    var busy = (-0.3, 1.5)
    var fall: (Double, Double)?
    var fan: (Double, Double)?
    var under: (Double, Double)?
    var splash: [(Double, Double, Double)] = []
    var chill = 0.0
    var burst: (Double, Double, Double)?
    var landings: [Double] = []
    var lid: (on: Bool, at: Double)?
    var glow: (Double, Double)?
    var foam: (Double, Double, Double)?
    var slide: (Double, Double)?
    var shake: (Double, Double)?
    var gusts = false
    var backPot = false
    var crossings: [Double] = []
}

extension Stage {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func script() -> Script {
        var random = SeededRandom(name: name + "/script")
        let view = self.view, rimY = view.rimY
        let t0 = 6 + random.range(-0.15, 0.15), pace = 1 / speed
        let over = NormPoint(x: view.potCenterX + random.range(-0.03, 0.03), y: rimY - lift)
        let out = NormPoint(x: entry, y: -0.04)
        let side = entry >= 0.5 ? 1.0 : -1.0
        let shoulder = NormPoint(x: 0.5 + (entry - 0.5) * 1.3, y: -0.35)
        let foreshortening = random.range(0.55, 0.85), stance = random.range(0.2, 0.7)
        let moreJoints = Int((2 * grip).rounded()), moreConfidence = 0.08 * grip
        let T = { (x: Double) in t0 + x * pace }

        func k(_ t: Double, _ p: NormPoint, dx: Double = 0, dy: Double = 0, open: Double? = nil, grip: Grip? = nil, joints: Int? = nil) -> HandKey {
            HandKey(t: T(t), x: p.x + dx, y: p.y + dy, openness: open, grip: grip, joints: joints.map { $0 + moreJoints })
        }
        func hand(
            _ keys: [HandKey], _ grip: Grip, joints: Int, confidence: Double, openness: Double = 1, prop: Prop = .none
        ) -> HandTrack {
            let base = HandKey(t: 0, x: 0, y: 0, openness: openness, grip: grip, joints: joints + moreJoints, confidence: confidence + moreConfidence)
            var track = HandTrack(.cook, keys: keys, base: base)
            track.prop = prop
            track.size = handSize
            track.foreshortening = foreshortening
            track.sleeve = sleeve
            track.skin = skin
            track.longSleeve = longSleeve
            track.shoulder = shoulder
            return track
        }
        func circles(_ start: Double, _ stop: Double, around center: NormPoint) -> [HandKey] {
            stride(from: start, through: stop, by: 0.1).map { t in
                let a = 2 * Double.pi * (t - start) / 1.2
                return k(t, center, dx: 0.06 * cos(a), dy: -0.02 + 0.02 * sin(a))
            }
        }
        func stir(_ start: Double, _ stop: Double, around center: NormPoint = over) -> HandTrack {
            hand([k(start - 0.6, out)] + circles(start, stop, around: center) + [k(stop + 0.5, out)], .partial, joints: 8, confidence: 0.72, prop: .spoon)
        }

        var hands: [HandTrack] = []
        var e = Effects()
        switch action {
        case let .add(food, method):
            e.chill = food.chill
            if food.vessel == .skillet { e.burst = (0.3, 4, 0.35) }
            switch method {
            case .pour, .slowPour, .shake, .pourThenStir:
                let length = method == .slowPour ? 4.8 : 1.4
                let prop: Prop = method == .shake || food == .penne ? .box : food == .rice ? .cup : .bag
                let wobble = method == .shake ? 0.025 : 0.012
                let pours = (0...Int(length / 0.15)).map { i in k(Double(i) * 0.15, over, dx: i % 2 == 0 ? wobble : -wobble, dy: 0.01) }
                let leave = method == .pourThenStir ? k(length + 0.4, over) : k(length + 0.6, out)
                hands.append(hand([k(-0.7, out), k(-0.1, over)] + pours + [leave], .grip, joints: 8, confidence: 0.76, prop: prop))
                if food == .spaghetti { e.fan = (0.2, length) } else { e.fall = (0.1, length) }
                e.splash = [(0.2, length, method == .slowPour ? 0.3 : 0.6)]
                e.busy = (-0.3, length + 0.5)
                if method == .pourThenStir {
                    hands.append(hand(circles(length + 0.5, length + 8, around: over) + [k(length + 8.5, out)], .partial, joints: 8, confidence: 0.72, prop: .spoon))
                    e.under = (length + 1, length + 5)
                    e.busy.1 = length + 8.2
                }
            case .toss:
                var toss = hand([
                    k(-0.35, NormPoint(x: entry, y: 0.08)), k(0, NormPoint(x: over.x + 0.08 * side, y: over.y - 0.05)),
                    k(0.12, over, open: 1.7, grip: .open, joints: 15), k(0.3, NormPoint(x: over.x - 0.1 * side, y: over.y - 0.07)),
                    k(0.55, NormPoint(x: 1 - entry, y: -0.02)),
                ], .grip, joints: 10, confidence: 0.7)
                toss.extraDropout = 0.1
                hands.append(toss)
                if food == .spaghetti { e.fan = (0.1, 0.4) } else { e.fall = (0.1, 0.4) }
                e.splash = [(0.15, 0.5, 0.6)]
                e.busy = (-0.3, 0.4)
            case .handful:
                hands.append(hand([
                    k(-0.6, out), k(-0.1, over, dy: 0.01), k(0.5, over, dy: 0.02),
                    k(0.75, over, dy: 0.02, open: 1.8, grip: .open, joints: 17), k(1.2, over), k(1.7, out, open: 1.6),
                ], .grip, joints: 11, confidence: 0.8))
                if food == .spaghetti { e.fan = (0.7, 1.1) } else { e.fall = (0.7, 1.0) }
                e.splash = [(0.7, 1.0, 0.4)]
                e.busy = (-0.3, 1.3)
            case .spoon, .tongs, .lay:
                let prop: Prop = method == .spoon ? .spoon : method == .tongs ? .tongs : .none
                let dip = method == .spoon && food == .eggs ? 1.3 : 0.6
                let bottom = NormPoint(x: over.x, y: rimY - (method == .lay ? 0.05 : 0.16))
                var keys = [k(-0.6, out), k(-0.1, over)]
                for piece in 0..<food.pieces {
                    let at = Double(piece) * (dip + 0.5), dx = Double(piece - food.pieces / 2) * 0.04
                    keys += [
                        k(at, over, dx: dx), k(at + dip * 0.6, bottom, dx: dx, open: method == .lay ? 1.35 : nil),
                        k(at + dip, over, dx: dx, open: method == .lay ? 1.05 : nil),
                    ]
                    if food == .chicken { e.landings.append(at + dip * 0.6) }
                    e.splash.append((at + dip * 0.5, at + dip * 0.8, food == .eggs ? 0.15 : 0.3))
                }
                let end = Double(food.pieces) * (dip + 0.5)
                keys.append(k(end + 0.4, out))
                let grip: Grip = method == .lay ? .grip : .partial
                hands.append(hand(keys, grip, joints: method == .lay ? 9 : 7, confidence: 0.72, openness: method == .lay ? 1.05 : 1, prop: prop))
                e.busy = (-0.3, end)
            case .pinch:
                hands.append(hand([
                    k(-0.6, out), k(-0.1, over, dy: 0.02), k(0.2, over, dy: 0.02, open: 1.3), k(0.4, over, dy: 0.02, open: 1.1),
                    k(0.6, over, dy: 0.02, open: 1.35), k(0.9, over, dy: 0.02, open: 1.15), k(1.4, out),
                ], .pinch, joints: 13, confidence: 0.74, openness: 1.1))
                e.busy = (-0.3, 1.1)
            case .scrape:
                let boardAt = NormPoint(x: over.x + 0.18 * side, y: rimY - 0.17)
                var board = hand([
                    k(-0.7, NormPoint(x: entry + 0.04 * side, y: 0.02)), k(-0.1, boardAt), k(2.8, boardAt, dx: 0.005), k(3.4, out),
                ], .grip, joints: 7, confidence: 0.7, prop: .board)
                board.shoulder = NormPoint(x: 0.5 + 0.45 * side, y: -0.2)
                let scrapes = (0..<8).map { k(0.3 * Double($0), over, dx: $0 % 2 == 0 ? 0.05 : -0.05, dy: -0.03) }
                hands += [board, hand([k(-0.4, out)] + scrapes + [k(3.0, out)], .partial, joints: 6, confidence: 0.65, prop: .knife)]
                e.fall = (0.3, 2.4)
                e.busy = (-0.3, 3.0)
            }
        case let .chore(chore):
            switch chore {
            case .stir:
                let length = random.range(3, 8)
                hands.append(stir(0, length))
                e.splash = [(0, length, 0.15)]
                e.busy = (-0.3, length + 0.2)
            case .taste:
                hands.append(hand([
                    k(-0.6, out), k(-0.1, over, dy: -0.05), k(0.4, over), k(0.8, over, dy: -0.06), k(1.3, NormPoint(x: entry - 0.1 * side, y: -0.04)),
                ], .partial, joints: 8, confidence: 0.72, prop: .spoon))
                e.busy = (-0.3, 1.0)
            case .lidOn:
                var lid = hand([
                    k(-0.8, out), k(-0.1, over, dy: 0.09), k(0.6, NormPoint(x: over.x, y: rimY - 0.14)),
                    k(0.9, NormPoint(x: over.x, y: rimY - 0.10)), k(1.3, out),
                ], .grip, joints: 7, confidence: 0.74, prop: .lid)
                lid.propWindow = (T(-1))...(T(0.9))
                hands.append(lid)
                e.lid = (true, 0.9)
            case .lidOff:
                var lid = hand([
                    k(-0.7, out), k(0, NormPoint(x: over.x, y: rimY - 0.10)), k(0.5, NormPoint(x: over.x, y: rimY - 0.10)),
                    k(1.0, NormPoint(x: over.x + 0.06, y: rimY - 0.22)), k(1.6, out),
                ], .grip, joints: 7, confidence: 0.74, prop: .lid)
                lid.propWindow = (T(0.5))...(T(2))
                hands.append(lid)
                e.lid = (false, 0.5)
                e.burst = (0.5, 3.5, 0.4)
            case .hover:
                // Feeling for the heat: an open hand, palm down, held over the pot.
                hands.append(hand([k(-0.6, out), k(-0.1, over, dy: 0.02), k(1.6, over, dy: 0.03), k(2.2, out)], .open, joints: 15, confidence: 0.76, openness: 1.6))
                e.busy = (-0.3, 1.8)
            case .wipe:
                let low = min(0.74, rimY + 0.1), reach = view.potCenterX - CounterView.region.x
                let swipes = (0..<7).map { k(0.5 * Double($0), NormPoint(x: view.potCenterX + ($0 % 2 == 0 ? -1 : 1) * reach * 0.7, y: low)) }
                hands.append(hand([k(-0.7, out)] + swipes + [k(3.6, out)], .grip, joints: 8, confidence: 0.7, prop: .towel))
                e.busy = (-0.3, 3.2)
            case .mitt:
                let handle = NormPoint(x: view.potCenterX + side * (vessel == .skillet ? 0.19 : 0.13), y: rimY + (vessel == .skillet ? -0.02 : 0.02))
                var mitt = hand([k(-0.7, out), k(0, handle), k(0.5, handle), k(1.2, handle, dx: 0.02 * side), k(1.6, handle, dx: 0.02 * side), k(2.2, out)], .grip, joints: 5, confidence: 0.45)
                mitt.mitt = true
                hands.append(mitt)
                e.slide = (0.5, 1.2)
                e.busy = (-0.3, 1.8)
            case .child:
                let from = NormPoint(x: entry < 0.5 ? 0.18 : 0.82, y: 0.92)
                let near = NormPoint(x: view.potCenterX - side * 0.12, y: rimY - 0.05)
                var child = hand([k(-0.5, from), k(0.2, near), k(0.8, near, dx: 0.02 * side, dy: -0.02), k(1.3, from)], .open, joints: 14, confidence: 0.7, openness: 1.6)
                child.size = 0.15
                child.shoulder = NormPoint(x: from.x, y: 1.2)
                hands.append(child)
                e.busy = (0, 0)
            case .phone:
                hands.append(stir(0.5, 2.5))
                e.glow = (0, 6)
                e.busy = (0.2, 2.7)
            case .boilOver:
                hands.append(stir(1.0, 4.0))
                e.foam = (0, 2.5, 4)
                e.busy = (0.7, 4.2)
            case .backPot:
                hands.append(stir(0, 5, around: NormPoint(x: over.x + 0.1, y: over.y - 0.08)))
                e.backPot = true
                e.busy = (-0.3, 5.2)
            case .reachPast:
                let y = rimY - 0.2
                var there = hand([k(-0.4, NormPoint(x: 0.95, y: y - 0.03)), k(0.3, NormPoint(x: 0.5, y: y)), k(0.8, NormPoint(x: 0.02, y: y - 0.05))], .open, joints: 15, confidence: 0.74)
                var back = hand([k(3.5, NormPoint(x: 0.02, y: y - 0.05)), k(4.0, NormPoint(x: 0.5, y: y + 0.01)), k(4.5, NormPoint(x: 0.95, y: y - 0.03))], .grip, joints: 9, confidence: 0.74)
                there.extraDropout = 0.08
                back.extraDropout = 0.08
                hands += [there, back]
                e.busy = (-0.4, 4.5)
            case .move:
                let grab = NormPoint(x: view.potCenterX + side * 0.17, y: rimY - 0.03)
                if vessel == .skillet {
                    let shakes = (0..<13).map { k(0.12 * Double($0), grab, dx: $0 % 2 == 0 ? 0.0125 : -0.0125) }
                    hands.append(hand([k(-0.7, out)] + shakes + [k(2.1, out)], .grip, joints: 8, confidence: 0.72))
                    e.shake = (0, 1.5)
                } else {
                    hands.append(hand([k(-0.7, out), k(0, grab), k(0.5, grab), k(1.2, grab, dx: 0.02 * side), k(2.0, out)], .grip, joints: 8, confidence: 0.72))
                    e.slide = (0.5, 1.2)
                }
                e.busy = (-0.3, 1.8)
            case .steam:
                e.gusts = true
                e.busy = (0, 0)
            }
        }
        for walker in 0..<walkers {
            let start = random.range(-3, 3) + 4.5 * Double(walker)
            e.crossings.append(start)
            var swing = HandTrack(.passerby, keys: [
                HandKey(t: T(start) + 0.5, x: 0.32, y: rimY - 0.08), HandKey(t: T(start) + 1.0, x: 0.58, y: rimY - 0.06),
            ], base: HandKey(t: 0, x: 0, y: 0, openness: 1, grip: .open, joints: 8, confidence: 0.5))
            swing.size = 0.12
            hands.append(swing)
        }

        let fx = e, color = food.color
        let steamLevel = steam * (vessel == .stockPot ? 1 : 0.35), boilLevel = boil * (vessel == .stockPot ? 1 : 0.6)
        let p1 = random.range(0, 6.28), p2 = random.range(0, 6.28)
        let scene: (Double) -> SceneState = { t in
            let drop = 1 - fx.chill * ramp(t, T(1), T(1) + 2)
            var s = SceneState(steam: steamLevel * drop, boil: boilLevel * drop)
            if fx.gusts {
                let gust = max(0, sin(t * 1.3 + p1)) * max(0, sin(t * 0.37 + p2))
                s.steam = min(1, 0.45 + 0.3 * ramp(t, 0, 10) + 0.5 * gust)
            }
            if let b = fx.burst { s.steam = min(1, s.steam + b.2 * pulse(t, T(b.0), T(b.1))) }
            if let f = fx.fan { s.spaghetti = ramp(t, T(f.0), T(f.1)) * (fx.under.map { 1 - 0.85 * ramp(t, T($0.0), T($0.1)) } ?? 1) }
            if let f = fx.fall { s.falling = pulse(t, T(f.0), T(f.1), edge: 0.05) }
            for (a, b, level) in fx.splash { s.splash += level * pulse(t, T(a), T(b)) }
            s.pile = fx.landings.filter { t >= T($0) }.count
            if let lid = fx.lid {
                s.lidSeated = lid.on ? t >= T(lid.at) : t < T(lid.at)
                if s.lidSeated { s.steam = 0.04; s.boil = 0.05 }
            }
            if let g = fx.glow { s.glow = pulse(t, T(g.0), T(g.1), edge: 0.1) }
            if let f = fx.foam { s.foam = f.2 * (ramp(t, T(f.0), T(f.0) + 1.5) - 0.7 * ramp(t, T(f.1), T(f.1) + 2)) }
            if let m = fx.slide { s.potShift = 2 * side * ramp(t, T(m.0), T(m.1)) }
            if let m = fx.shake { s.potShift = 2 * sin(2 * .pi * (t - T(m.0)) / 0.24) * pulse(t, T(m.0), T(m.1)) }
            s.backPot = fx.backPot
            s.food = color
            if fx.busy.1 > fx.busy.0 {
                s.cookNear = t < T(fx.busy.1)
                    ? 0.5 + 0.5 * ramp(t, T(fx.busy.0) - 0.6, T(fx.busy.0))
                    : stance + (1 - stance) * (1 - ramp(t, T(fx.busy.1), T(fx.busy.1) + 1))
            }
            for start in fx.crossings where t >= T(start) && t <= T(start) + 1.8 {
                s.walkerColumn = -10 + 84 * (t - T(start)) / 1.8
            }
            return s
        }
        return Script(eventTime: t0, hands: hands, scene: scene)
    }
}

extension Stage {
    /// The hand-written held-out set: about 30 situations the tuned suite never shows.
    static func holdout() -> [Stage] {
        let sun = Lighting.afternoonSun, cabinet = Lighting.underCabinet, bulb = Lighting.dimBulb
        let deep = Color3(y: 95, cb: 118, cr: 142), fair = Color3(y: 188, cb: 112, cr: 146)
        func s(_ name: String, _ food: Food, _ action: Action, _ light: Lighting, _ surface: Surface, _ finish: PotKind,
               _ tweak: (inout Stage) -> Void = { _ in }) -> Stage {
            var stage = Stage("holdout/" + name, food, action)
            stage.light = light
            stage.surface = surface
            stage.finish = finish
            tweak(&stage)
            return stage
        }
        return [
            // Adds.
            s("penne shaken, big pot low in the box", .penne, .add(.penne, .shake), sun, .butcherBlock, .copper) { $0.rim = 0.58; $0.potWidth = 0.84 },
            s("penne shaken, small pot to the left", .penne, .add(.penne, .shake), cabinet, .patternTile, .enamel) { $0.potWidth = 0.45; $0.potCenter = 0.38 },
            s("rice from a cup, camera low", .rice, .add(.rice, .pour), bulb, .blackQuartz, .nonstick) { $0.rim = 0.31 },
            s("rice from a cup, small hand, long sleeve", .rice, .add(.rice, .pour), cabinet, .butcherBlock, .enamel) {
                $0.handSize = 0.21; $0.skin = deep; $0.longSleeve = true; $0.sleeve = Color3(y: 200, cb: 128, cr: 128)
            },
            s("eggs on a spoon, sun", .eggs, .add(.eggs, .spoon), sun, .patternTile, .enamel),
            s("eggs on a spoon, dim, pot to the right", .eggs, .add(.eggs, .spoon), bulb, .butcherBlock, .copper) { $0.potWidth = 0.5; $0.potCenter = 0.63 },
            s("broccoli by the handful, quartz", .broccoli, .add(.broccoli, .handful), cabinet, .blackQuartz, .nonstick),
            s("broccoli tossed fast, long sleeve", .broccoli, .add(.broccoli, .toss), sun, .patternTile, .copper) {
                $0.speed = 1.6; $0.longSleeve = true; $0.sleeve = Color3(y: 40, cb: 150, cr: 110)
            },
            s("chicken laid with tongs", .chicken, .add(.chicken, .tongs), cabinet, .butcherBlock, .nonstick),
            s("chicken laid by a small hand, dim", .chicken, .add(.chicken, .lay), bulb, .blackQuartz, .copper) { $0.handSize = 0.22; $0.skin = fair },
            s("spaghetti poured, wide pot, camera high", .spaghetti, .add(.spaghetti, .pour), cabinet, .blackQuartz, .nonstick) {
                $0.rim = 0.6; $0.potWidth = 0.78; $0.potCenter = 0.56
            },
            s("spaghetti tossed, dim tile", .spaghetti, .add(.spaghetti, .toss), bulb, .patternTile, .enamel) { $0.entry = 0.2 },
            s("garlic pinched, sun on quartz", .garlic, .add(.garlic, .pinch), sun, .blackQuartz, .copper) { $0.skin = deep },
            s("garlic off a board, camera low", .garlic, .add(.garlic, .scrape), cabinet, .patternTile, .enamel) { $0.rim = 0.56 },
            s("broccoli with tongs, someone behind", .broccoli, .add(.broccoli, .tongs), bulb, .butcherBlock, .steel) { $0.walkers = 1 },
            s("penne poured then stirred", .penne, .add(.penne, .pourThenStir), sun, .blackQuartz, .nonstick) { $0.lift = 0.16 },
            // Not adds.
            s("oven mitt slides the pot", .spaghetti, .chore(.mitt), sun, .butcherBlock, .copper),
            s("oven mitt on the skillet handle", .chicken, .chore(.mitt), cabinet, .patternTile, .nonstick),
            s("wiping the stove, dim", .rice, .chore(.wipe), bulb, .blackQuartz, .enamel),
            s("wiping beside the skillet, sun", .garlic, .chore(.wipe), sun, .patternTile, .steel),
            s("phone lights up while stirring, dim", .penne, .chore(.phone), bulb, .butcherBlock, .nonstick),
            s("phone lights up while stirring, LEDs", .eggs, .chore(.phone), cabinet, .blackQuartz, .copper),
            s("boiling over, stirred down", .spaghetti, .chore(.boilOver), cabinet, .patternTile, .steel) { $0.steam = 0.8; $0.boil = 0.9 },
            s("boiling over, small pot, dim", .broccoli, .chore(.boilOver), bulb, .butcherBlock, .enamel) { $0.potWidth = 0.48 },
            s("second pot behind, stirred", .rice, .chore(.backPot), sun, .blackQuartz, .nonstick),
            s("second pan behind the skillet", .chicken, .chore(.backPot), cabinet, .butcherBlock, .copper),
            s("child's hand reaching, sun", .eggs, .chore(.child), sun, .patternTile, .enamel) { $0.entry = 0.2 },
            s("child's hand reaching, dim", .penne, .chore(.child), bulb, .blackQuartz, .copper),
            s("open hand feeling the heat", .broccoli, .chore(.hover), cabinet, .butcherBlock, .steel) {
                $0.handSize = 0.22; $0.longSleeve = true; $0.sleeve = Color3(y: 120, cb: 128, cr: 128)
            },
            s("stirring, camera low, two people behind", .spaghetti, .chore(.stir), sun, .patternTile, .copper) { $0.rim = 0.32; $0.walkers = 2 },
        ]
    }

    /// Fixed master seeds for the stress run. The suite and the hand-written holdout seed from
    /// their situations' names; these seed from "stress/<seed>/<index>", so none are shared.
    static let stressSeeds: [UInt64] = [20_261_104, 7_340_117, 55_512_093]

    /// `count` situations with every factor drawn on its own from a wide, plausible range.
    /// Whether one is an add is drawn too, and its expected outcome follows from that alone.
    // swiftlint:disable:next function_body_length
    static func stress(count: Int, seed: UInt64) -> [Stage] {
        (0..<count).map { index in
            var r = SeededRandom(name: "stress/\(seed)/\(index)")
            func pick<T>(_ options: [T]) -> T { options[min(options.count - 1, Int(r.unit() * Double(options.count)))] }
            func bucket(_ value: Double, _ low: Double, _ high: Double, _ names: [String]) -> String {
                value < low ? names[0] : value > high ? names[2] : names[1]
            }
            let food = pick(Food.allCases)
            let action: Action
            if r.chance(0.5) {
                action = .add(food, pick(food.methods))
            } else {
                var chores = Chore.allCases
                if food.vessel == .skillet { chores.removeAll { $0 == .boilOver } }
                action = .chore(pick(chores))
            }
            var stage = Stage("stress/\(seed)/\(index) \(action.label)", food, action)
            let stock = food.vessel == .stockPot
            stage.rim = stock ? r.range(0.28, 0.62) : r.range(0.52, 0.80)
            stage.potWidth = stock ? r.range(0.40, 0.88) : r.range(0.55, 0.92)
            let room = max(0, min(0.14, 0.46 - stage.potWidth / 2))
            stage.potCenter = 0.5 + r.range(-room, room)

            var light = Lighting(gain: r.range(0.35, 1.5), noise: 0, chromaNoise: 0)
            let dim = max(0, 1 - light.gain)
            light.noise = 1.5 + 5 * dim + r.range(0, 0.8)
            light.chromaNoise = 1 + 3.5 * dim
            light.crShift = r.range(-10, 14)
            light.cbShift = -0.9 * light.crShift + r.range(-3, 3)
            light.shadowDepth = r.range(0.1, 0.45)
            let flicker = r.unit()
            if flicker < 0.25 {
                light.banding = r.range(0.05, 0.18)
                light.bandPeriod = r.range(14, 30)
                light.bandRoll = r.range(0.03, 0.12)
            } else if flicker < 0.5 {
                light.flicker = r.range(0.02, 0.08)
            }
            let sunny = r.chance(0.25)
            if sunny { light.sunShadow = r.range(0.15, 0.45) }
            stage.light = light
            stage.surface = pick([.wood, .granite, .white, .glossy, .butcherBlock, .blackQuartz, .patternTile])
            stage.finish = pick([.steel, .dark, .light, .copper, .enamel, .nonstick])
            stage.steam = r.range(0.1, 0.9)
            stage.boil = r.range(0.2, 0.9)
            stage.handSize = r.range(0.20, 0.32)
            let tone = Int(r.unit() * 3)
            stage.skin = [Color3(y: 188, cb: 112, cr: 146), Color3.skin, Color3(y: 95, cb: 118, cr: 142)][min(2, tone)]
            stage.sleeve = pick([
                Color3(y: 60, cb: 145, cr: 118), Color3(y: 120, cb: 128, cr: 128), Color3(y: 90, cb: 110, cr: 175),
                Color3(y: 215, cb: 128, cr: 128), Color3(y: 35, cb: 128, cr: 128),
            ])
            stage.longSleeve = r.chance(0.4)
            stage.speed = exp(r.range(log(0.6), log(1.8)))
            stage.entry = r.range(0.1, 0.9)
            stage.lift = r.range(0.12, 0.30)
            stage.grip = r.range(-1, 1)
            let people = r.unit()
            stage.walkers = people < 0.6 ? 0 : people < 0.9 ? 1 : 2
            stage.name = "stress/\(seed)/\(index) \(action.label)"

            let rimRange = stock ? (0.28, 0.62) : (0.52, 0.80)
            let rimShare = (stage.rim - rimRange.0) / (rimRange.1 - rimRange.0)
            stage.factors = [
                ("pot size", bucket(stage.potWidth / (stock ? 0.62 : 0.72), 0.85, 1.15, ["small", "medium", "large"])),
                ("pot position", bucket(stage.potCenter - 0.5, -0.05, 0.05, ["left", "middle", "right"])),
                ("pot finish", stage.finish.rawValue),
                ("camera height", bucket(rimShare, 0.33, 0.67, ["rim high in box (camera low)", "rim mid box", "rim low in box (camera high)"])),
                ("light level", bucket(light.gain, 0.65, 1.15, ["dim", "medium", "bright"])),
                ("light color", bucket(light.crShift, -3, 6, ["cool", "neutral", "warm"])),
                ("flicker", light.banding > 0 ? "LED bands" : light.flicker > 0 ? "dimmer wobble" : "none"),
                ("sun shadows", sunny ? "moving" : "none"),
                ("counter", stage.surface.rawValue),
                ("steam", bucket(stage.steam, 0.37, 0.63, ["light", "medium", "heavy"])),
                ("boil", bucket(stage.boil, 0.43, 0.67, ["low", "medium", "hard"])),
                ("hand size", bucket(stage.handSize, 0.24, 0.28, ["small", "medium", "large"])),
                ("skin tone", ["light", "medium", "deep"][min(2, tone)]),
                ("sleeve", stage.longSleeve ? "long" : "short"),
                ("speed", bucket(stage.speed, 0.85, 1.25, ["slow", "normal", "fast"])),
                ("path", (stage.entry < 0.37 ? "from left" : stage.entry > 0.63 ? "from right" : "from above")
                    + (stage.lift < 0.18 ? ", low" : stage.lift > 0.24 ? ", high" : ", mid")),
                ("grip", bucket(stage.grip, -0.33, 0.33, ["hard to see", "fair", "clear"])),
                ("people behind", ["none", "one", "two"][stage.walkers]),
                ("step", food.rawValue),
            ]
            switch action {
            case let .add(food, method):
                stage.factors += [("ingredient", food.rawValue), ("how it goes in", method.rawValue)]
            case let .chore(chore):
                stage.factors.append(("non-add", chore.rawValue))
            }
            return stage
        }
    }
}
