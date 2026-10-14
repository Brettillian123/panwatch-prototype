import Foundation

/// Tunable numbers for `AdditionDetector`. Times are in seconds; fractions are of the
/// pan region's pixels.
struct DetectorSettings: Codable, Equatable, Sendable {
    /// How long a hand must be over the pan before its visit counts.
    var minimumDwell = 0.3
    /// How long the hand must be gone before the visit is over. Bridges frames where
    /// hand tracking blinks.
    var exitHold = 0.5
    /// A frame is still when less than this fraction of the pan changed since the last frame.
    var stillnessThreshold = 0.015
    /// How long the pan must stay still before the after-picture is taken.
    var settleHold = 0.35
    /// Take the after-picture anyway once this much time has passed, because steam and
    /// bubbles never stop moving.
    var maximumSettleWait = 3.0
    /// Brightness difference (0-255) for a pixel to count as changed.
    var lumaThreshold = 24.0
    /// Color difference, |ΔCb| + |ΔCr|, for a pixel to count as changed.
    var chromaThreshold = 22.0
    /// Fraction of the pan that must differ between before and after to call it an addition.
    var additionThreshold = 0.03
    /// Reject a decision when the whole pan got uniformly brighter or darker.
    var lightingVeto = true
    /// Median brightness shift that counts as a lighting change rather than food.
    var lightingShiftThreshold = 16.0
    /// Ignore new visits for this long after reporting an addition.
    var cooldown = 3.0
    /// The before-picture is taken at least this long before the hand arrived, so the
    /// arm's shadow isn't in it.
    var baselineLag = 0.3
    /// Stillness needed after arming before watching starts.
    var warmUpDuration = 0.6
    /// When off, any motion in the pan starts a visit even if no hand is seen.
    var requireHand = true
    /// With `requireHand` off, frame-to-frame change above this starts a visit.
    var motionActivityThreshold = 0.06
    /// The hand zone is the pan region grown by this fraction on every side, because a
    /// hand pouring from above sits over the rim, not inside the box.
    var handZoneMargin = 0.25

    var changeRule: ChangeRule {
        ChangeRule(lumaThreshold: lumaThreshold, chromaThreshold: chromaThreshold)
    }
}

/// What the detector needs from one analyzed camera frame.
struct FrameObservation: Sendable {
    /// Capture time in seconds. Only differences between frames matter.
    var time: Double
    /// Whether a tracked hand is inside the hand zone around the pan.
    var handInZone: Bool
    /// The pan region, sampled from this frame.
    var region: PanPatch
}

/// The verdict after a hand visited the pan and left.
struct DetectorDecision: Identifiable, Sendable {
    enum Outcome: String, Sendable {
        case addition
        case noChange
        case lightingChange
    }

    let id: Int
    let time: Double
    let outcome: Outcome
    /// Fraction of the pan that differs between before and after.
    let changedFraction: Double
    /// The `additionThreshold` in force when the decision was made.
    let additionThreshold: Double
    /// Median brightness change, used by the lighting veto.
    let medianLumaShift: Double
    /// Seconds the hand spent over the pan.
    let dwell: Double
    /// False when the pan never stopped moving and the after-picture was taken at the time limit.
    let settledCleanly: Bool
    let before: PanPatch
    let after: PanPatch
}

/// Decides whether something was added to the pan, from a stream of per-frame observations.
///
/// The trigger is geometric first and photometric second. A hand has to spend time over
/// the pan and then leave; only then is the pan compared with how it looked just before
/// the hand arrived. Lighting drift, steam, and people walking past never reach the
/// comparison unless a hand actually visited the pan. The recipe decides whether the
/// detector is armed at all, so stirring during a "simmer" step is never judged.
struct AdditionDetector {
    enum Phase: String, Sendable {
        /// The current recipe step doesn't need the camera.
        case disarmed
        /// Learning what the pan looks like before anything happens.
        case warmingUp
        /// Ready; waiting for a hand.
        case watching
        /// A hand is over the pan.
        case handInPan
        /// The hand left; waiting for the pan to stop moving.
        case settling
        /// Just reported an addition.
        case cooldown
    }

    private struct Snapshot {
        let time: Double
        let patch: PanPatch
    }

    /// How much recent still history to keep for choosing the before-picture.
    private static let historyDuration = 3.0
    /// Warm-up gives up waiting for perfect stillness after this long.
    private static let warmUpPatience = 3.0
    /// A median brightness shift only counts as lighting when at least this share of the
    /// pan moved by about that much. Without it, pasta covering more than half of a dark
    /// pan moves the median as far as a light does and is thrown away.
    private static let lightingEvenness = 0.8

    var settings: DetectorSettings

    private(set) var phase: Phase = .disarmed
    /// Seconds the current or last visit's hand has spent over the pan.
    private(set) var dwell = 0.0
    /// Fraction of the pan that changed since the previous frame.
    private(set) var motion = 0.0
    /// Fraction of the pan that differs from the current before-picture.
    private(set) var liveChange = 0.0

    private var isArmed = false
    private var history: [Snapshot] = []
    private var frozenBaseline: PanPatch?
    private var previous: PanPatch?
    private var lastTime: Double?
    private var warmUpStart: Double?
    private var lastActiveTime = 0.0
    private var settleStart = 0.0
    private var stillSince: Double?
    private var cooldownUntil = 0.0
    private var decisionCount = 0

    init(settings: DetectorSettings = DetectorSettings()) {
        self.settings = settings
    }

    mutating func setArmed(_ armed: Bool) {
        guard armed != isArmed else { return }
        isArmed = armed
        reset()
    }

    /// Forgets everything about the scene, for example after the pan box moved.
    mutating func reset() {
        history.removeAll()
        frozenBaseline = nil
        previous = nil
        lastTime = nil
        warmUpStart = nil
        stillSince = nil
        dwell = 0
        motion = 0
        liveChange = 0
        phase = isArmed ? .warmingUp : .disarmed
    }

    /// Feeds one frame. Returns a decision when a visit to the pan has just been judged.
    mutating func process(_ frame: FrameObservation) -> DetectorDecision? {
        let t = frame.time
        let dt = lastTime.map { min(max(t - $0, 0), 0.25) } ?? 0
        lastTime = t
        let rule = settings.changeRule
        motion = previous.map { frame.region.changedFraction(from: $0, rule: rule) } ?? 0
        previous = frame.region

        guard isArmed else {
            phase = .disarmed
            liveChange = 0
            return nil
        }
        if phase == .disarmed { phase = .warmingUp }

        let active = frame.handInZone || (!settings.requireHand && motion > settings.motionActivityThreshold)
        let still = motion < settings.stillnessThreshold
        let reference = frozenBaseline ?? history.last?.patch
        liveChange = reference.map { frame.region.changedFraction(from: $0, rule: rule) } ?? 0

        switch phase {
        case .disarmed, .warmingUp:
            let started = warmUpStart ?? t
            warmUpStart = started
            let impatient = t - started >= Self.warmUpPatience
            if !active && (still || impatient) { remember(frame) }
            if let first = history.first, let last = history.last,
               last.time - first.time >= settings.warmUpDuration || (impatient && !active) {
                phase = .watching
            }

        case .watching:
            if active {
                beginVisit(at: t)
            } else if still {
                remember(frame)
            }

        case .handInPan:
            if active {
                dwell += dt
                lastActiveTime = t
            } else if t - lastActiveTime >= settings.exitHold {
                if dwell >= settings.minimumDwell {
                    phase = .settling
                    settleStart = t
                    stillSince = nil
                } else {
                    // A hand passing over on its way somewhere else. Not worth judging.
                    endVisit()
                }
            }

        case .settling:
            if active {
                phase = .handInPan
                lastActiveTime = t
                return nil
            }
            if still {
                stillSince = stillSince ?? t
            } else {
                stillSince = nil
            }
            let settled = stillSince.map { t - $0 >= settings.settleHold } ?? false
            if settled || t - settleStart >= settings.maximumSettleWait {
                return decide(frame, settledCleanly: settled)
            }

        case .cooldown:
            if t >= cooldownUntil { phase = .watching }
            if still && !active { remember(frame) }
        }
        return nil
    }

    private mutating func remember(_ frame: FrameObservation) {
        history.append(Snapshot(time: frame.time, patch: frame.region))
        let horizon = frame.time - Self.historyDuration
        history.removeAll { $0.time < horizon }
    }

    private mutating func beginVisit(at t: Double) {
        let cutoff = t - settings.baselineLag
        guard let baseline = history.last(where: { $0.time <= cutoff }) ?? history.first else { return }
        frozenBaseline = baseline.patch
        dwell = 0
        lastActiveTime = t
        phase = .handInPan
    }

    private mutating func endVisit() {
        frozenBaseline = nil
        dwell = 0
        phase = .watching
    }

    private mutating func decide(_ frame: FrameObservation, settledCleanly: Bool) -> DetectorDecision? {
        guard let before = frozenBaseline else {
            endVisit()
            return nil
        }
        let after = frame.region
        let changed = after.changedFraction(from: before, rule: settings.changeRule)
        let shift = after.medianLumaShift(from: before)

        let outcome: DetectorDecision.Outcome
        if settings.lightingVeto && abs(shift) >= settings.lightingShiftThreshold
            && after.fractionShifted(by: shift, within: max(settings.lumaThreshold, abs(shift) / 2), from: before)
                >= Self.lightingEvenness {
            outcome = .lightingChange
        } else if changed >= settings.additionThreshold {
            outcome = .addition
        } else {
            outcome = .noChange
        }

        decisionCount += 1
        let decision = DetectorDecision(
            id: decisionCount,
            time: frame.time,
            outcome: outcome,
            changedFraction: changed,
            additionThreshold: settings.additionThreshold,
            medianLumaShift: shift,
            dwell: dwell,
            settledCleanly: settledCleanly,
            before: before,
            after: after
        )

        // Whatever happened, the pan as it looks now is the new normal.
        frozenBaseline = nil
        history = [Snapshot(time: frame.time, patch: after)]
        if outcome == .addition {
            phase = .cooldown
            cooldownUntil = frame.time + settings.cooldown
        } else {
            phase = .watching
        }
        return decision
    }
}
