import Foundation

/// Everything Vision said about one hand in one frame: how sure it is that this is a hand,
/// and every joint it placed with how sure it is of each, faint ones included. The app
/// records these and the replay reads them back, so both decide which hands count by the
/// same rules.
struct HandReading: Equatable, Sendable {
    /// Vision's 21 hand joints, numbered for the recording format.
    enum JointName: UInt8, CaseIterable, Sendable {
        case wrist
        case thumbCMC, thumbMP, thumbIP, thumbTip
        case indexMCP, indexPIP, indexDIP, indexTip
        case middleMCP, middlePIP, middleDIP, middleTip
        case ringMCP, ringPIP, ringDIP, ringTip
        case littleMCP, littlePIP, littleDIP, littleTip

        static let tips: [JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
    }

    struct Joint: Equatable, Sendable {
        var name: JointName
        /// Normalized image coordinates, origin at the top left.
        var point: NormPoint
        /// How sure Vision is of this joint, 0-1.
        var confidence: Double
    }

    /// Why a hand Vision saw doesn't count.
    enum Rejection: Equatable, Sendable {
        /// Vision isn't sure enough it's a hand.
        case lowConfidence(Double)
        /// Too few joints Vision is sure of.
        case fewJoints(Int)
        /// Enough joints for an open hand but no wrist, and not sure enough to go without one.
        case noWrist
    }

    /// How sure Vision is that this is a hand, 0-1.
    var confidence: Double
    var joints: [Joint]

    /// The joints Vision is sure enough of to use.
    func confidentJoints(_ settings: DetectorSettings) -> [Joint] {
        joints.filter { $0.confidence >= settings.jointConfidence }
    }

    /// Nil when the hand counts. A hand in plain view shows its wrist and most fingers. One
    /// gripping a bag or a handful of pasta hides them, so it counts with fewer joints and
    /// no wrist when Vision is surer it's a hand.
    func rejection(_ settings: DetectorSettings) -> Rejection? {
        let confident = confidentJoints(settings)
        let hasWrist = confident.contains { $0.name == .wrist }
        let openHand = confidence >= settings.handConfidence && confident.count >= settings.minimumHandJoints && hasWrist
        let holding = confidence >= settings.holdingHandConfidence && confident.count >= settings.holdingHandJoints
        if openHand || holding { return nil }
        if confidence < min(settings.handConfidence, settings.holdingHandConfidence) { return .lowConfidence(confidence) }
        if confident.count < min(settings.minimumHandJoints, settings.holdingHandJoints) { return .fewJoints(confident.count) }
        return hasWrist ? .fewJoints(confident.count) : .noWrist
    }

    /// The hand as the detector uses it, or nil when it doesn't count. `aspect` is the
    /// frame's width over its height, for measuring how open the hand is.
    func tracked(_ settings: DetectorSettings, aspect: Double) -> TrackedHand? {
        guard rejection(settings) == nil else { return nil }
        let confident = confidentJoints(settings)
        func point(_ name: JointName) -> NormPoint? { confident.first { $0.name == name }?.point }
        let openness = HandGeometry.openness(
            wrist: point(.wrist),
            palm: point(.middleMCP),
            tips: JointName.tips.compactMap { point($0) },
            aspect: aspect
        )
        return TrackedHand(joints: confident.map(\.point), openness: openness)
    }
}
