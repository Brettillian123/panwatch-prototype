import Foundation
@testable import PanWatchCore

/// Vision's 21 hand joints.
enum Joint: Int, CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// The tips `HandPoseDetector` measures openness with, thumb first.
    static let tips: [Joint] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
}

/// How the hand is held, which decides the joints Vision can still see.
enum Grip: Sendable {
    /// Fingers spread, all in view.
    case open
    /// Wrapped around a bag, a box, a cup, a lid or a handle: the fingertips are hidden.
    case grip
    /// Holding a utensil: thumb and index in view, the rest curled behind it.
    case partial
    /// Fingertips together, rubbing out a pinch.
    case pinch

    /// Joints in the order Vision keeps them as the hand gets harder to see.
    var visibility: [Joint] {
        switch self {
        case .open:
            [.wrist, .middleMCP, .indexMCP, .ringMCP, .littleMCP, .thumbCMC, .thumbMP, .indexTip, .middleTip, .ringTip, .thumbTip,
             .littleTip, .indexPIP, .middlePIP, .ringPIP, .thumbIP, .littlePIP, .indexDIP, .middleDIP, .ringDIP, .littleDIP]
        case .grip:
            [.wrist, .thumbCMC, .thumbMP, .indexMCP, .middleMCP, .thumbIP, .ringMCP, .littleMCP, .thumbTip, .indexPIP, .middlePIP,
             .ringPIP, .littlePIP, .indexDIP, .middleDIP, .ringDIP, .littleDIP, .indexTip, .middleTip, .ringTip, .littleTip]
        case .partial:
            [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip, .indexMCP, .indexPIP, .middleMCP, .indexDIP, .indexTip, .ringMCP,
             .middlePIP, .littleMCP, .middleDIP, .ringPIP, .littlePIP, .middleTip, .ringDIP, .littleDIP, .ringTip, .littleTip]
        case .pinch:
            [.wrist, .thumbCMC, .indexMCP, .middleMCP, .thumbMP, .thumbTip, .indexTip, .middleTip, .thumbIP, .indexPIP, .ringMCP,
             .littleMCP, .middlePIP, .ringTip, .indexDIP, .middleDIP, .ringPIP, .littlePIP, .ringDIP, .littleTip, .littleDIP]
        }
    }
}

/// One point on a hand's path. Unset values carry over from the key before.
struct HandKey: Sendable {
    var t: Double
    var x: Double
    var y: Double
    /// True openness in palm lengths: about 1 for a fist, 1.8 for an open hand.
    var openness: Double? = nil
    var grip: Grip? = nil
    /// Joints Vision is confident about.
    var joints: Int? = nil
    /// Vision's overall confidence.
    var confidence: Double? = nil
}

/// A hand over time, as Vision would follow it.
struct HandTrack: Sendable {
    enum Source: Sendable {
        /// The cook's hand: real, painted into the picture.
        case cook
        /// A "hand" Vision finds in wood grain or a shiny bag. Nothing to paint.
        case phantom
        /// The swinging hand of someone walking behind, painted as part of their body.
        case passerby
    }

    struct State {
        var point: NormPoint
        var openness: Double
        var grip: Grip
        var joints: Int
        var confidence: Double
        /// Frame heights a second.
        var speed: Double
    }

    var source: Source = .cook
    var keys: [HandKey]
    var prop: Prop = .none
    /// When the hand holds `prop`; nil means the whole time.
    var propWindow: ClosedRange<Double>? = nil
    /// Wrist to middle fingertip, in frame heights.
    var size = 0.28
    var shoulder = NormPoint(x: 0.88, y: -0.35)
    /// For phantoms: share of frames Vision reports it.
    var presence = 1.0
    /// Frame-to-frame wobble of the whole hand, in frame heights.
    var jitter = 0.004
    var extraDropout = 0.0
    /// From the counter the hand is seen from the side, so fingers opening toward or away
    /// from the camera look shorter. 1 is a hand seen face on.
    var foreshortening = 0.7
    var sleeve = Color3(y: 60, cb: 145, cr: 118)
    var skin = Color3.skin
    /// A sleeve down to the wrist, so no forearm skin shows.
    var longSleeve = false
    /// An oven mitt instead of a bare hand.
    var mitt = false

    init(_ source: Source = .cook, keys: [HandKey], base: HandKey) {
        self.source = source
        var last = base
        self.keys = keys.sorted { $0.t < $1.t }.map { key in
            var filled = key
            filled.openness = key.openness ?? last.openness
            filled.grip = key.grip ?? last.grip
            filled.joints = key.joints ?? last.joints
            filled.confidence = key.confidence ?? last.confidence
            last = filled
            return filled
        }
    }

    func state(at t: Double) -> State? {
        guard let first = keys.first, let last = keys.last, t >= first.t, t <= last.t else { return nil }
        let after = keys.firstIndex { $0.t >= t } ?? keys.count - 1
        let b = keys[after], a = keys[max(0, after - 1)]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 1
        let dx = (b.x - a.x) * CounterView.aspect, dy = b.y - a.y
        return State(
            point: NormPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f),
            openness: a.openness! + (b.openness! - a.openness!) * f,
            grip: f >= 1 ? b.grip! : a.grip!,
            joints: f >= 1 ? b.joints! : a.joints!,
            confidence: a.confidence! + (b.confidence! - a.confidence!) * f,
            speed: span > 0 ? (dx * dx + dy * dy).squareRoot() / span : 0
        )
    }

    func holds(at t: Double) -> Prop {
        guard let window = propWindow else { return prop }
        return window.contains(t) ? prop : .none
    }

    /// What Vision reports for this hand in the frame at `t`, before any of the app's checks.
    func observe(at t: Double, in environment: Environment, random: inout SeededRandom) -> VisionHand? {
        guard let s = state(at: t) else { return nil }
        guard s.point.x > -0.05, s.point.x < 1.05, s.point.y > -0.05, s.point.y < 1.05 else { return nil }
        // Missed frames: the room's rate plus motion blur on fast moves. Phantoms come and go.
        let miss = source == .phantom ? 1 - presence : environment.dropout + extraDropout + (s.speed > 0.6 ? 0.2 : 0)
        if random.chance(miss) { return nil }
        let confidence = min(1, max(0, s.confidence + environment.confidenceShift + 0.07 * random.gaussian()))
        let count = min(21, max(0, s.joints + environment.jointShift + Int((1.2 * random.gaussian()).rounded())))
        let wristSeen = random.chance(source == .phantom ? 0.8 : 0.96)

        // The hand's shape in frame heights, x stretched by the aspect so lengths are true.
        var dx = (s.point.x - shoulder.x) * CounterView.aspect, dy = s.point.y - shoulder.y
        let norm = max(1e-6, (dx * dx + dy * dy).squareRoot())
        dx /= norm
        dy /= norm
        func along(_ angle: Double, _ length: Double) -> (Double, Double) {
            let c = cos(angle), n = sin(angle)
            return ((dx * c - dy * n) * length, (dx * n + dy * c) * length)
        }
        let palm = size * 0.42
        let seenOpen = 1 + (s.openness - 1) * foreshortening
        let spread = 0.5 + 0.5 * min(1, max(0, (s.openness - 1) / 0.8))
        var shape = [Joint: (Double, Double)]()
        shape[.wrist] = (0, 0)
        shape[.thumbCMC] = along(-0.9, palm * 0.3)
        shape[.thumbMP] = along(-0.8, palm * 0.6)
        let fingers: [(mcp: Joint, pip: Joint, dip: Joint, tip: Joint, angle: Double, mcpLength: Double, tipLength: Double)] = [
            (.thumbMP, .thumbIP, .thumbIP, .thumbTip, -0.75, 0.6, 0.85),
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.25, 0.95, 0.97),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, 0, 1.0, 1.05),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.2, 0.95, 1.0),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.4, 0.88, 0.88),
        ]
        for finger in fingers {
            let mcp = finger.mcp == .thumbMP ? shape[.thumbMP]! : along(finger.angle * 0.35, palm * finger.mcpLength)
            let tip = along(finger.angle * spread, palm * seenOpen * finger.tipLength)
            shape[finger.mcp] = mcp
            shape[finger.tip] = tip
            // Curled fingers bow out to the side of the line from knuckle to tip.
            let curl = (1.8 - s.openness) * palm * 0.08
            if finger.pip == finger.dip {
                shape[finger.pip] = (mcp.0 + (tip.0 - mcp.0) * 0.5 - dy * curl, mcp.1 + (tip.1 - mcp.1) * 0.5 + dx * curl)
            } else {
                shape[finger.pip] = (mcp.0 + (tip.0 - mcp.0) * 0.45 - dy * curl, mcp.1 + (tip.1 - mcp.1) * 0.45 + dx * curl)
                shape[finger.dip] = (mcp.0 + (tip.0 - mcp.0) * 0.75 - dy * curl, mcp.1 + (tip.1 - mcp.1) * 0.75 + dx * curl)
            }
        }
        // Place the whole hand so its 21-joint middle sits on the path, plus wobble.
        let mean = Joint.allCases.reduce((0.0, 0.0)) { ($0.0 + shape[$1]!.0, $0.1 + shape[$1]!.1) }
        let offsetX = s.point.x * CounterView.aspect - mean.0 / 21 + jitter * random.gaussian()
        let offsetY = s.point.y - mean.1 / 21 + jitter * random.gaussian()

        // Which joints Vision is sure of: the grip's order, shuffled a little.
        var order = s.grip.visibility.filter { $0 != .wrist }
        let swaps = source == .phantom ? 12 : 4
        for _ in 0..<swaps {
            let i = Int(random.range(0, Double(order.count - 1)))
            if random.chance(0.5) { order.swapAt(i, i + 1) }
        }
        var kept = Array(order.prefix(max(0, wristSeen ? count - 1 : count)))
        if wristSeen && count > 0 { kept.append(.wrist) }

        var joints = [Joint: NormPoint]()
        for joint in kept {
            let p = shape[joint]!
            joints[joint] = NormPoint(
                x: (p.0 + offsetX + environment.jointNoise * random.gaussian()) / CounterView.aspect,
                y: p.1 + offsetY + environment.jointNoise * random.gaussian()
            )
        }
        return VisionHand(confidence: confidence, joints: joints)
    }

    /// How to paint this hand at `t`, or nil if it isn't the cook's or isn't there.
    func painted(at t: Double, in view: CounterView) -> PaintedHand? {
        guard source == .cook, let s = state(at: t) else { return nil }
        return PaintedHand(
            center: view.patch(s.point), shoulder: view.patch(shoulder),
            length: size * view.pixelsPerFrameHeight, openness: s.openness, sleeve: sleeve, prop: holds(at: t),
            skin: skin, longSleeve: longSleeve, mitt: mitt
        )
    }
}

/// One hand as Vision reports it: overall confidence and the joints it is confident about.
struct VisionHand: Sendable {
    var confidence: Double
    var joints: [Joint: NormPoint]

    /// The hand as the app reads it from Vision: every joint Vision is sure of, sure enough to use.
    var reading: HandReading {
        HandReading(confidence: confidence, joints: Joint.allCases.compactMap { joint in
            joints[joint].map { HandReading.Joint(name: HandReading.JointName(rawValue: UInt8(joint.rawValue))!, point: $0, confidence: 0.8) }
        })
    }

    /// The joints in a fixed order, so sums come out the same on every run.
    var orderedJoints: [NormPoint] { Joint.allCases.compactMap { joints[$0] } }
}

/// The app's own checks on what Vision found, exactly as `HandPoseDetector.hands(in:settings:)`
/// makes them: enough confidence, enough joints with the wrist among them, and openness from
/// the wrist, the middle knuckle and at least three fingertips.
func trackedHands(_ seen: [VisionHand], settings: DetectorSettings) -> [TrackedHand] {
    seen.compactMap { hand in
        guard hand.confidence >= settings.handConfidence,
              hand.joints.count >= settings.minimumHandJoints,
              let wrist = hand.joints[.wrist] else { return nil }
        let openness = HandGeometry.openness(
            wrist: wrist,
            palm: hand.joints[.middleMCP],
            tips: Joint.tips.compactMap { hand.joints[$0] },
            aspect: CounterView.aspect
        )
        return TrackedHand(joints: hand.orderedJoints, openness: openness)
    }
}
