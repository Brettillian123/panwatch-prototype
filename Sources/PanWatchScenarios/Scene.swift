import Foundation
@testable import PanWatchCore

enum Surface: String, Sendable {
    case wood, granite, white, glossy
    case butcherBlock = "butcher block", blackQuartz = "black quartz", patternTile = "pattern tile"
}
enum PotKind: String, Sendable { case steel, dark, light, copper, enamel, nonstick }
enum Vessel: String, Sendable { case stockPot = "stock pot", skillet }

/// How the kitchen is lit. The app locks exposure and white balance while it watches, so
/// nothing here gets corrected.
struct Lighting: Sendable {
    /// Brightness multiplier; above 1 pushes pale things into clipping.
    var gain: Double
    /// Sensor noise per patch pixel, after the 3x3 average the sampler does.
    var noise: Double
    var chromaNoise: Double
    /// White balance cast: Cb down and Cr up is warm.
    var cbShift = 0.0
    var crShift = 0.0
    /// LED flicker caught by the rolling shutter: bands of brightness, as a fraction.
    var banding = 0.0
    var bandPeriod = 22.0
    /// How far the bands roll each analyzed frame, in cycles.
    var bandRoll = 0.0
    /// How much the cook's body darkens what it shades.
    var shadowDepth = 0.3
    /// Afternoon sun through a window: a soft shadow that drifts across the box, as a fraction.
    var sunShadow = 0.0
    /// The whole picture brightening and dimming from frame to frame (a bulb on a dimmer).
    var flicker = 0.0
}

struct Environment: Sendable {
    let name: String
    let surface: Surface
    let pot: PotKind
    let lighting: Lighting
    /// Share of frames Vision misses a real hand in.
    let dropout: Double
    /// Added to Vision's confidence for every hand.
    let confidenceShift: Double
    /// Added to the confident joint count.
    let jointShift: Int
    /// Joint position noise, in frame heights.
    let jointNoise: Double

    static let brightWood = Environment(
        name: "bright wood", surface: .wood, pot: .dark,
        lighting: Lighting(gain: 1.35, noise: 1.5, chromaNoise: 1.0, shadowDepth: 0.4),
        dropout: 0.04, confidenceShift: 0.03, jointShift: 0, jointNoise: 0.003
    )
    static let dimGranite = Environment(
        name: "dim granite", surface: .granite, pot: .light,
        lighting: Lighting(gain: 0.5, noise: 4.5, chromaNoise: 3.0, cbShift: -12, crShift: 10, shadowDepth: 0.15),
        dropout: 0.15, confidenceShift: -0.12, jointShift: -2, jointNoise: 0.006
    )
    static let ledSteel = Environment(
        name: "LED steel", surface: .glossy, pot: .steel,
        lighting: Lighting(
            gain: 1.0, noise: 2.0, chromaNoise: 1.5, cbShift: 8, crShift: -6,
            banding: 0.12, bandPeriod: 22, bandRoll: 0.07, shadowDepth: 0.3
        ),
        dropout: 0.07, confidenceShift: -0.03, jointShift: 0, jointNoise: 0.004
    )
    static let whiteSteel = Environment(
        name: "white steel", surface: .white, pot: .steel,
        lighting: Lighting(gain: 1.15, noise: 1.8, chromaNoise: 1.2, shadowDepth: 0.35),
        dropout: 0.05, confidenceShift: 0, jointShift: 0, jointNoise: 0.003
    )
}

/// The pan box as a phone propped on the counter sees it, looking across at the side of the
/// pot from about 70 cm. One patch pixel is about 6 mm, and pixels are square.
struct CounterView: Sendable {
    static let frameWidth = 1280
    static let frameHeight = 720
    static let aspect = Double(frameWidth) / Double(frameHeight)
    /// The box the cook draws: the top of the pot's side, the rim, and the space above it.
    static let region = NormRect(x: 0.30, y: 0.36, width: 0.40, height: 0.40)

    let width: Int
    let height: Int
    let vessel: Vessel
    /// First row of the rim. Everything above it is the space over the pot.
    let rimRow: Int
    let potLeft: Int
    let potRight: Int
    /// First row of the stovetop under a skillet; a stock pot fills the box to the bottom.
    let floorRow: Int

    init(vessel: Vessel) {
        let size = PanPatch.size(for: Self.region, frameWidth: Self.frameWidth, frameHeight: Self.frameHeight)
        width = size.width
        height = size.height
        self.vessel = vessel
        switch vessel {
        case .stockPot:
            rimRow = height * 16 / 36
            potLeft = width * 12 / 64
            potRight = width * 52 / 64
            floorRow = height
        case .skillet:
            rimRow = height * 24 / 36
            potLeft = width * 9 / 64
            potRight = width * 55 / 64
            floorRow = height * 33 / 36
        }
    }

    /// Where a frame point lands in the patch, as (column, row).
    func patch(_ point: NormPoint) -> (c: Double, r: Double) {
        (
            (point.x - Self.region.x) / Self.region.width * Double(width),
            (point.y - Self.region.y) / Self.region.height * Double(height)
        )
    }

    /// Another pot size or place in the box, or the camera a little higher or lower: the rim
    /// row, the pot's sides and the stovetop as fractions of the box.
    init(vessel: Vessel, rim: Double, left: Double, right: Double, floor: Double = 1) {
        let size = PanPatch.size(for: Self.region, frameWidth: Self.frameWidth, frameHeight: Self.frameHeight)
        width = size.width
        height = size.height
        self.vessel = vessel
        rimRow = min(height - 3, max(5, Int((Double(height) * rim).rounded())))
        potLeft = max(2, Int((Double(width) * left).rounded()))
        potRight = min(width - 2, max(potLeft + 10, Int((Double(width) * right).rounded())))
        floorRow = floor >= 1 ? height : min(height, max(rimRow + 3, Int((Double(height) * floor).rounded())))
    }

    /// The middle of the pot, across the frame.
    var potCenterX: Double { Self.region.x + Double(potLeft + potRight) / 2 / Double(width) * Self.region.width }
    /// The rim's height in the frame.
    var rimY: Double { Self.region.y + Double(rimRow) / Double(height) * Self.region.height }
    /// Patch pixels per frame height.
    var pixelsPerFrameHeight: Double { Double(height) / Self.region.height }
}

/// Everything in view that changes over a scenario, apart from hands.
struct SceneState {
    /// Steam rising off the pot, 0-1.
    var steam = 0.5
    /// Heat shimmer just above the rim, 0-1.
    var boil = 0.5
    /// Share of the spaghetti fan standing above the rim.
    var spaghetti = 0.0
    var lidSeated = false
    /// How far the pot has been slid, in patch columns.
    var potShift = 0.0
    /// The range-hood light, 0 off to 1 on.
    var hoodLight = 0.0
    /// The cook's body close to the stove: its shadow and its reflection in steel, 0-1.
    var cookNear = 0.0
    var cookColumn = 40.0
    /// A person walking behind the stove, by patch column.
    var walkerColumn: Double? = nil
    /// Droplets thrown up by something going in, 0-1.
    var splash = 0.0
    /// A phone screen lighting up beside the stove, 0-1.
    var glow = 0.0
    /// Boil-over foam standing above the rim, in patch rows.
    var foam = 0.0
    /// Food pieces resting high enough to show over the rim, like chicken in a low pan.
    var pile = 0
    /// Pieces in the air on their way in, 0-1.
    var falling = 0.0
    var food = Color3(y: 205, cb: 98, cr: 145)
    /// A second pot on the back burner, showing over the front one's rim.
    var backPot = false
}

struct Color3: Sendable {
    var y: Double
    var cb: Double
    var cr: Double

    static let skin = Color3(y: 165, cb: 110, cr: 150)
    static let steel = Color3(y: 175, cb: 129, cr: 127)
}

enum Prop: Sendable { case none, bag, box, cup, spoon, tongs, board, knife, lid, towel }

/// A cook's hand as it should be painted into the patch this frame.
struct PaintedHand {
    var center: (c: Double, r: Double)
    var shoulder: (c: Double, r: Double)
    /// Hand length, wrist to fingertip, in patch pixels.
    var length: Double
    var openness: Double
    var sleeve: Color3
    var prop: Prop
    var skin = Color3.skin
    var longSleeve = false
    var mitt = false
}

/// Paints the pan box frame by frame: backdrop, pot, contents, steam, hands, then light and noise.
struct SceneRenderer {
    let view: CounterView
    let environment: Environment
    private var random: SeededRandom
    private var backdrop: [Color3]
    private var strands: [[(index: Int, alpha: Double)]]
    private var blobs: [Blob] = []

    private struct Blob {
        var c, r, radius, opacity, vc, vr: Double
        var age = 0.0
        var life: Double
    }

    init(view: CounterView, environment: Environment, seed: String) {
        self.view = view
        self.environment = environment
        random = SeededRandom(name: seed + "/render")
        backdrop = []
        strands = []
        backdrop = makeBackdrop()
        strands = makeStrands()
    }

    private mutating func makeBackdrop() -> [Color3] {
        var plane: [Color3] = []
        let phase = random.range(0, 6.28)
        for r in 0..<view.height {
            for c in 0..<view.width {
                let x = Double(c), y = Double(r)
                switch environment.surface {
                case .wood:
                    let grain = sin(y * 1.7 + 2.5 * sin(x * 0.13 + phase)) + 0.4 * sin(y * 4.1 + x * 0.05)
                    plane.append(Color3(y: 115 + 16 * grain + 5 * random.gaussian(), cb: 108 + 2 * random.gaussian(), cr: 150 + 4 * grain))
                case .granite:
                    let speck = random.unit()
                    let base = speck < 0.15 ? 55.0 : speck > 0.88 ? 170.0 : 105 + 14 * random.gaussian()
                    plane.append(Color3(y: base, cb: 126 + 3 * random.gaussian(), cr: 131 + 3 * random.gaussian()))
                case .white:
                    plane.append(Color3(y: 222 - 0.4 * y + 1.5 * random.gaussian(), cb: 128, cr: 129))
                case .glossy:
                    let grout = c % 16 == 0 || r % 12 == 0
                    let highlight = 110 * exp(-pow(x - 20 - 0.3 * y, 2) / 18)
                    plane.append(Color3(y: (grout ? 150 : 70) + highlight + 2 * random.gaussian(), cb: 134, cr: 124))
                case .butcherBlock:
                    let strip = c / 5, tone = [0.0, 18, -14][strip % 3]
                    let grain = 4 * sin(y * 0.8 + Double(strip) * 2)
                    plane.append(Color3(y: 140 + tone + grain + 4 * random.gaussian(), cb: 104 + 2 * random.gaussian(), cr: 152 + 0.2 * tone))
                case .blackQuartz:
                    let fleck = random.unit() > 0.94
                    plane.append(Color3(y: fleck ? 150 : 22 + 3 * random.gaussian(), cb: 128, cr: 128))
                case .patternTile:
                    let motif = (c + r) % 10 < 2 || (c - r + 120) % 10 < 2
                    let grout = c % 10 == 0 || r % 10 == 0
                    plane.append(Color3(
                        y: grout ? 200 : (motif ? 75 : 190) + 2 * random.gaussian(), cb: motif && !grout ? 150 : 126, cr: motif && !grout ? 112 : 130
                    ))
                }
            }
        }
        return plane
    }

    /// Spaghetti ends fanning up past the rim: thin strands that cover part of each pixel.
    private mutating func makeStrands() -> [[(index: Int, alpha: Double)]] {
        let center = Double(view.potLeft + view.potRight) / 2
        return (0..<26).map { _ in
            let base = random.range(Double(view.potLeft) + 8, Double(view.potRight) - 8)
            let lean = (base - center) * 0.35 + 2.5 * random.gaussian()
            let length = random.range(7, 14)
            var pixels: [Int: Double] = [:]
            let steps = Int(length * 2)
            for step in 0...steps {
                let f = Double(step) / Double(steps)
                let r = Int((Double(view.rimRow) - 0.3 - length * f).rounded(.down))
                let c = Int((base + lean * f).rounded())
                guard r >= 0, r < view.rimRow, c >= 0, c < view.width else { continue }
                pixels[r * view.width + c] = random.range(0.3, 0.5)
            }
            return pixels.keys.sorted().map { ($0, pixels[$0]!) }
        }
    }

    mutating func render(_ s: SceneState, hands: [PaintedHand], frame: Int) -> PanPatch {
        let w = view.width, h = view.height
        let left = Double(view.potLeft) + s.potShift
        let right = Double(view.potRight) + s.potShift
        let time = Double(frame) / 15
        var plane = [Color3](repeating: Color3(y: 0, cb: 128, cr: 128), count: w * h)

        // Heat shimmer: the backdrop just above the rim wobbles sideways a pixel or so.
        var shimmer = [Int](repeating: 0, count: h)
        for r in max(0, view.rimRow - 5)..<view.rimRow {
            shimmer[r] = Int((random.gaussian() * s.boil * 0.8).rounded())
        }

        for r in 0..<h {
            for c in 0..<w {
                let x = Double(c)
                let overPot = x >= left && x < right
                let sc = overPot ? min(w - 1, max(0, c + shimmer[r])) : c
                var p = backdrop[r * w + sc]
                if let walker = s.walkerColumn, r < view.floorRow {
                    let cover = min(1, max(0, 9 - abs(x - walker)))
                    p = blend(p, Color3(y: 60 + 6 * sin(Double(r) * 0.9), cb: 140, cr: 122), cover)
                }
                if s.backPot, r >= view.rimRow - 7, r < view.rimRow, x >= (left + right) / 2 - 4, x < right + 10 {
                    p = Color3(y: r == view.rimRow - 7 ? 195 : 115 + 20 * sin(x * 0.5), cb: 128, cr: 128)
                }
                if r >= view.floorRow {
                    p = Color3(y: c % 6 == 0 ? 62 : 32, cb: 128, cr: 128)
                }
                p = paintPot(p, r: r, x: x, left: left, right: right, state: s, time: time, hands: hands)
                // The cook's body shades the backdrop and the pot.
                let shade = environment.lighting.shadowDepth * s.cookNear * exp(-pow(x - s.cookColumn, 2) / 392)
                p.y *= 1 - shade
                plane[r * w + c] = p
            }
        }

        if s.lidSeated { paintLid(&plane, left: left, right: right) }
        paintSpaghetti(&plane, share: s.spaghetti, shift: Int(s.potShift.rounded()))
        paintSplash(&plane, level: s.splash, left: left, right: right)
        paintFood(&plane, state: s, left: left, right: right, time: time)
        paintSteam(&plane, level: s.steam, left: left, right: right)
        for hand in hands { paint(hand, on: &plane, left: left, right: right) }
        return expose(plane, state: s, frame: frame)
    }

    private func paintPot(
        _ p: Color3, r: Int, x: Double, left: Double, right: Double, state s: SceneState, time: Double, hands: [PaintedHand]
    ) -> Color3 {
        guard r >= view.rimRow, r < view.floorRow else { return p }
        let width = right - left
        // Side handles on a stock pot; a long handle off to the right on a skillet.
        let handle: Bool
        switch view.vessel {
        case .stockPot: handle = r >= view.rimRow + 2 && r <= view.rimRow + 4 && ((x >= left - 4 && x < left) || (x >= right && x < right + 4))
        case .skillet: handle = r <= view.rimRow + 1 && x >= right
        }
        let cover = min(1, max(0, x + 1 - left)) * min(1, max(0, right - x))
        if cover <= 0 { return handle ? blend(p, potColor(r: view.rimRow + 1, x: x, left: left, width: width, state: s, time: time, hands: hands), 1) : p }
        return blend(p, potColor(r: r, x: x, left: left, width: width, state: s, time: time, hands: hands), cover)
    }

    private func potColor(r: Int, x: Double, left: Double, width: Double, state s: SceneState, time: Double, hands: [PaintedHand]) -> Color3 {
        let rim = r - view.rimRow
        switch environment.pot {
        case .steel:
            if rim == 0 { return Color3(y: 215, cb: 128, cr: 128) }
            if rim == 1 { return Color3(y: 160, cb: 128, cr: 128) }
            // Steel mirrors the room: bright and dark bands that drift, the cook, and any hand nearby.
            let b1 = left + 0.22 * width + 2.5 * sin(0.35 * time)
            let b2 = left + 0.55 * width + 2.0 * sin(0.27 * time + 1)
            let b3 = left + 0.80 * width + 1.5 * sin(0.5 * time + 2)
            var y = 125 + 70 * exp(-pow(x - b1, 2) / 6) - 45 * exp(-pow(x - b2, 2) / 10) + 50 * exp(-pow(x - b3, 2) / 4)
            y -= 50 * s.cookNear * exp(-pow(x - s.cookColumn, 2) / 60)
            var cr = 127.0
            for hand in hands where hand.center.r > -10 && hand.center.r < Double(view.rimRow) + 4 {
                let near = exp(-pow(x - hand.center.c, 2) / 24)
                y += 25 * near
                cr += 10 * near
            }
            return Color3(y: y, cb: 129, cr: cr)
        case .dark:
            if rim == 0 { return Color3(y: 95, cb: 128, cr: 128) }
            if rim == 1 { return Color3(y: 55, cb: 128, cr: 128) }
            return Color3(y: 38 + 25 * exp(-pow(x - left - 0.3 * width, 2) / 5), cb: 128, cr: 128)
        case .light:
            if rim == 0 { return Color3(y: 232, cb: 126, cr: 130) }
            if rim == 1 { return Color3(y: 190, cb: 122, cr: 134) }
            let edge = (x - left - width / 2) / (width / 2)
            return Color3(y: 205 - 25 * edge * edge, cb: 120, cr: 136)
        case .copper:
            if rim == 0 { return Color3(y: 205, cb: 104, cr: 162) }
            if rim == 1 { return Color3(y: 140, cb: 110, cr: 158) }
            let band = left + 0.3 * width + 2 * sin(0.3 * time)
            let y = 115 + 65 * exp(-pow(x - band, 2) / 8) - 40 * s.cookNear * exp(-pow(x - s.cookColumn, 2) / 60)
            return Color3(y: y, cb: 106, cr: 164)
        case .enamel:
            if rim <= 1 { return Color3(y: rim == 0 ? 75 : 60, cb: 128, cr: 128) }
            return Color3(y: 92 + 70 * exp(-pow(x - left - 0.25 * width, 2) / 6), cb: 110, cr: 178)
        case .nonstick:
            if rim == 0 { return Color3(y: 125, cb: 128, cr: 128) }
            return Color3(y: 26 + 16 * exp(-pow(x - left - 0.6 * width, 2) / 12), cb: 129, cr: 127)
        }
    }

    private func paintLid(_ plane: inout [Color3], left: Double, right: Double) {
        let center = (left + right) / 2, half = (right - left) / 2
        for k in 1...5 {
            let r = view.rimRow - k
            guard r >= 0 else { continue }
            let span = k <= 3 ? half * (1 - pow(Double(k) / 3.6, 2)).squareRoot() : 2
            for c in 0..<view.width where abs(Double(c) + 0.5 - center) <= span {
                let shine = k == 2 && Double(c) < center ? 40.0 : 0
                plane[r * view.width + c] = Color3(y: 170 + shine, cb: 129, cr: 127)
            }
        }
    }

    private func paintSpaghetti(_ plane: inout [Color3], share: Double, shift: Int) {
        let shown = Int((share * Double(strands.count)).rounded())
        guard shown > 0 else { return }
        var clear = [Double](repeating: 1, count: plane.count)
        for strand in strands.prefix(shown) {
            for (index, alpha) in strand {
                let c = index % view.width + shift
                guard c >= 0, c < view.width else { continue }
                clear[index - index % view.width + c] *= 1 - alpha
            }
        }
        let pasta = Color3(y: 205, cb: 98, cr: 145)
        for index in plane.indices where clear[index] < 1 {
            plane[index] = blend(plane[index], pasta, 1 - clear[index])
        }
    }

    private mutating func paintSplash(_ plane: inout [Color3], level: Double, left: Double, right: Double) {
        guard level > 0 else { return }
        let count = Int(level * 5 + random.unit())
        for _ in 0..<count {
            let r = view.rimRow - 1 - Int(random.range(0, 4))
            let c = Int(random.range(left + 2, right - 2))
            guard r >= 0, c >= 0, c < view.width else { continue }
            plane[r * view.width + c] = blend(plane[r * view.width + c], Color3(y: 240, cb: 128, cr: 128), 0.5)
        }
    }

    private mutating func paintSteam(_ plane: inout [Color3], level: Double, left: Double, right: Double) {
        let rate = level * (view.vessel == .stockPot ? 2.2 : 1.2)
        let born = Int(rate) + (random.chance(rate - Double(Int(rate))) ? 1 : 0)
        let wind = 0.4 * sin(Double(blobs.count) * 0.1 + random.range(-0.2, 0.2))
        for _ in 0..<born {
            blobs.append(Blob(
                c: random.range(left + 3, right - 3), r: Double(view.rimRow) - 0.5,
                radius: random.range(1.5, 3), opacity: random.range(0.06, 0.18) * (0.4 + 0.6 * level),
                vc: 0.3 * random.gaussian() + wind, vr: -random.range(2.0, 3.5), life: random.range(5, 9)
            ))
        }
        let vapor = Color3(y: 232, cb: 128, cr: 128)
        for blob in blobs {
            let alpha = blob.opacity * (1 - blob.age / blob.life)
            let reach = Int(blob.radius * 2) + 1
            let rowLow = max(0, Int(blob.r) - reach), rowHigh = min(view.rimRow, view.height - 1, Int(blob.r) + reach)
            let columnLow = max(0, Int(blob.c) - reach), columnHigh = min(view.width - 1, Int(blob.c) + reach)
            guard rowLow <= rowHigh, columnLow <= columnHigh else { continue }
            for r in rowLow...rowHigh {
                for c in columnLow...columnHigh {
                    let d2 = pow(Double(c) - blob.c, 2) + pow(Double(r) - blob.r, 2)
                    let a = alpha * exp(-d2 / (2 * blob.radius * blob.radius))
                    if a > 0.005 { plane[r * view.width + c] = blend(plane[r * view.width + c], vapor, a) }
                }
            }
        }
        blobs = blobs.compactMap { blob in
            var next = blob
            next.c += next.vc
            next.r += next.vr
            next.radius += 0.35
            next.age += 1
            return next.age >= next.life || next.r < -next.radius * 2 ? nil : next
        }
    }

    /// Pieces flying in, pieces resting above a low rim, and boil-over foam.
    private mutating func paintFood(_ plane: inout [Color3], state s: SceneState, left: Double, right: Double, time: Double) {
        let w = view.width, span = right - left
        if s.falling > 0 {
            for _ in 0..<Int(s.falling * 6 + random.unit()) {
                let r = view.rimRow - 1 - Int(random.range(0, 12)), c = Int(random.range(left + 3, right - 3))
                guard r >= 0, c >= 0, c < w else { continue }
                plane[r * w + c] = blend(plane[r * w + c], s.food, 0.7)
            }
        }
        for piece in 0..<min(4, s.pile) {
            let middle = left + (0.25 + 0.17 * Double(piece)) * span, half = 0.09 * span
            for k in 1...3 {
                let r = view.rimRow - k, reach = half * (1 - pow(Double(k - 1) / 3.2, 2))
                guard r >= 0 else { continue }
                for c in max(0, Int(middle - reach))..<min(w, Int(middle + reach) + 1) {
                    plane[r * w + c] = Color3(y: s.food.y - 12 * Double(k) + 6 * sin(Double(c)), cb: s.food.cb, cr: s.food.cr)
                }
            }
        }
        if s.foam > 0.5 {
            for k in 1...max(1, Int(s.foam.rounded())) {
                let r = view.rimRow - k
                guard r >= 0 else { continue }
                for c in max(0, Int(left) + 1)..<min(w, Int(right)) where sin(Double(c) * 0.9 + time * 3) > Double(k) / s.foam - 1.2 {
                    plane[r * w + c] = blend(plane[r * w + c], Color3(y: 232, cb: 126, cr: 130), 0.85)
                }
            }
        }
    }

    /// An arm from the shoulder, a hand, and whatever it holds. The pot's near wall hides
    /// anything that dips below the rim.
    private func paint(_ hand: PaintedHand, on plane: inout [Color3], left: Double, right: Double) {
        let (hc, hr) = hand.center
        var dc = hc - hand.shoulder.c, dr = hr - hand.shoulder.r
        let norm = max(1e-6, (dc * dc + dr * dr).squareRoot())
        dc /= norm
        dr /= norm
        let wrist = (c: hc - dc * hand.length * 0.45, r: hr - dr * hand.length * 0.45)
        let elbow = (c: wrist.c - dc * 14, r: wrist.r - dr * 14)
        var shapes: [(Double, Double) -> Double] = []
        var colors: [Color3] = []
        func segment(_ a: (c: Double, r: Double), _ b: (c: Double, r: Double), radius: Double, _ color: Color3) {
            shapes.append { c, r in
                let vc = b.c - a.c, vr = b.r - a.r
                let t = min(1, max(0, ((c - a.c) * vc + (r - a.r) * vr) / max(1e-6, vc * vc + vr * vr)))
                let d = ((c - a.c - t * vc) * (c - a.c - t * vc) + (r - a.r - t * vr) * (r - a.r - t * vr)).squareRoot()
                return min(1, max(0, radius + 0.5 - d))
            }
            colors.append(color)
        }
        // Small hands (a child's) are thinner too; adult hands keep the suite's widths.
        let scale = hand.length < 21 ? max(0.5, hand.length / 25) : 1
        segment(hand.shoulder, elbow, radius: 6 * scale, hand.sleeve)
        segment(elbow, wrist, radius: 5 * scale, hand.longSleeve ? hand.sleeve : hand.skin)
        let open = min(1, max(0, (hand.openness - 1) / 0.8))
        let reach = hand.length * (0.30 + 0.25 * open)
        let palm = hand.mitt ? Color3(y: 196, cb: 120, cr: 142) : hand.skin
        segment(wrist, (c: wrist.c + dc * reach * 2, r: wrist.r + dr * reach * 2), radius: (hand.mitt ? 6.5 : 4.5 * scale) + 2 * open, palm)
        switch hand.prop {
        case .none: break
        case .bag: segment((hc, hr), (hc - 6, hr + 13), radius: 4, Color3(y: 190, cb: 105, cr: 140))
        case .box: segment((hc, hr), (hc - 4, hr + 12), radius: 5, Color3(y: 70, cb: 165, cr: 105))
        case .cup: segment((hc, hr), (hc - 3, hr + 6), radius: 4, Color3(y: 225, cb: 128, cr: 128))
        case .spoon: segment((hc, hr), (hc - 2, hr + 16), radius: 0.7, Color3(y: 150, cb: 115, cr: 145))
        case .tongs:
            segment((hc, hr), (hc - 1.5, hr + 16), radius: 0.6, Color3.steel)
            segment((hc, hr), (hc + 1.5, hr + 16), radius: 0.6, Color3.steel)
        case .board: segment((hc, hr + 2), (hc - 18, hr + 6), radius: 2, Color3(y: 165, cb: 110, cr: 148))
        case .towel: segment((hc - 5, hr + 2), (hc + 5, hr + 4), radius: 3, Color3(y: 215, cb: 135, cr: 120))
        case .knife: segment((hc, hr), (hc - 8, hr + 3), radius: 0.6, Color3.steel)
        case .lid:
            segment((hc - 16, hr + 7), (hc + 16, hr + 7), radius: 2, Color3.steel)
            segment((hc, hr + 3), (hc, hr + 5), radius: 1.5, Color3.steel)
        }
        for r in 0..<view.height {
            for c in 0..<view.width {
                let x = Double(c)
                if r >= view.rimRow, x >= left, x < right { continue }
                for (shape, color) in zip(shapes, colors) {
                    let cover = shape(x + 0.5, Double(r) + 0.5)
                    if cover > 0 { plane[r * view.width + c] = blend(plane[r * view.width + c], color, cover) }
                }
            }
        }
    }

    /// Light, flicker, clipping and sensor noise, then 8-bit planes.
    private mutating func expose(_ plane: [Color3], state s: SceneState, frame: Int) -> PanPatch {
        let light = environment.lighting
        let count = plane.count
        var luma = [UInt8](repeating: 0, count: count), cb = luma, cr = luma
        for index in 0..<count {
            let r = Double(index / view.width) / Double(view.height)
            var gain = light.gain
            // A range-hood light is above the pot: the top of the box brightens most.
            gain *= 1 + s.hoodLight * (0.25 + 0.85 * pow(1 - r, 1.5))
            if light.banding > 0 {
                gain *= 1 + light.banding * sin(2 * .pi * (r * Double(view.height) / light.bandPeriod + light.bandRoll * Double(frame)))
            }
            let column = Double(index % view.width)
            if light.sunShadow > 0 {
                let edge = (Double(frame) * 0.2).truncatingRemainder(dividingBy: Double(view.width) + 40) - 20
                gain *= 1 - light.sunShadow * exp(-pow(column - edge - 0.3 * r * Double(view.height), 2) / 60)
            }
            if light.flicker > 0 { gain *= 1 + light.flicker * sin(Double(frame) * 2.3) }
            let glow = s.glow > 0 ? s.glow * exp(-pow(column - 6, 2) / 300) : 0
            gain *= 1 + 0.4 * glow
            let p = plane[index]
            let y = p.y * gain + light.noise * random.gaussian()
            // Clipped highlights lose their color.
            let washed = min(1, max(0, (y - 235) / 40))
            let cbValue = 128 + (p.cb - 128 + light.cbShift - 6 * s.hoodLight + 12 * glow) * (1 - washed) + light.chromaNoise * random.gaussian()
            let crValue = 128 + (p.cr - 128 + light.crShift + 5 * s.hoodLight) * (1 - washed) + light.chromaNoise * random.gaussian()
            luma[index] = UInt8(min(255, max(0, y.rounded())))
            cb[index] = UInt8(min(255, max(0, cbValue.rounded())))
            cr[index] = UInt8(min(255, max(0, crValue.rounded())))
        }
        return PanPatch(width: view.width, height: view.height, luma: luma, cb: cb, cr: cr)
    }
}

func blend(_ a: Color3, _ b: Color3, _ alpha: Double) -> Color3 {
    Color3(y: a.y + (b.y - a.y) * alpha, cb: a.cb + (b.cb - a.cb) * alpha, cr: a.cr + (b.cr - a.cr) * alpha)
}
