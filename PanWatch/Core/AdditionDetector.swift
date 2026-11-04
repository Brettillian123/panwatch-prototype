import Foundation

/// Tunable numbers for `AdditionDetector`. Times are in seconds; fractions are of the
/// pan region's pixels.
struct DetectorSettings: Codable, Equatable, Sendable {
    /// How long a hand must be over the pan before its visit counts.
    var minimumDwell = 0.4
    /// A hand over the pan for longer than this is stirring or checking on the food, not
    /// adding something, so the visit is ignored.
    var maximumDwell = 6.0
    /// After stirring, a hand that comes back within this long is still stirring.
    var stirQuiet = 1.5
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
    /// Count a hand that opens over the pan as an addition. It catches ingredients held in
    /// the hand, like a handful of pasta, that the pot hides once they're in.
    var countRelease = true
    /// How far the hand must open, in palm lengths, to count as letting go.
    var releaseThreshold = 0.35
    /// Vision's overall confidence (0-1) a hand needs. It finds faint "hands" in wood grain
    /// and shiny bags; real ones score higher.
    var handConfidence = 0.5
    /// Confident joints a hand needs, the wrist among them. A hand holding a bag hides its
    /// fingers, so asking for more loses real hands.
    var minimumHandJoints = 6
    /// A hand within this distance (fraction of the frame) of where one was last frame is
    /// the same hand.
    var handMatchDistance = 0.10
    /// A hand counts once seen in this many of the last `handDebounceFrames` frames, so a
    /// one-frame flicker in a texture never counts.
    var handDebounceHits = 2
    /// See `handDebounceHits`.
    var handDebounceFrames = 3
    /// A hand that stays within this distance (fraction of the frame) of one spot for
    /// `handStillDuration` is texture, not a hand. A hand adding food moves.
    var handStillDistance = 0.015
    /// See `handStillDistance`.
    var handStillDuration = 2.0
    /// A hand ignored as still counts again once it moves this far (fraction of the frame)
    /// from where it sat. Well above `handStillDistance` so jitter can't flip it back.
    var handResumeDistance = 0.04
    /// Warm-up learns the pan from a frame with a hand in view after this long, so a hand
    /// that never leaves can't keep the pan from ever being learned.
    var warmUpGiveUp = 10.0
    /// Vision's confidence (0-1) a joint needs to be used at all. Wood grain yields many
    /// faint ones.
    var jointConfidence = 0.4
    /// A hand gripping a bag or a handful of pasta hides its fingers and often its wrist.
    /// A hand Vision is at least this sure of counts with only `holdingHandJoints` joints,
    /// wrist or not.
    var holdingHandConfidence = 0.6
    /// See `holdingHandConfidence`.
    var holdingHandJoints = 4
    /// On steps whose ingredient stays in sight (`minimumChange` above zero), count a change
    /// in the pan box that holds even when no counted hand visited: a pour whose hand
    /// Vision never trusted.
    var countVisibleChange = true
    /// Set per step by `applying(_:)` when the step's ingredient stays in sight. Off unless
    /// a step asks for it, so other steps never judge a change without a hand.
    var visibleIngredient = false
    /// The visible-change path needs this many times `additionThreshold` of the box to change.
    var visibleChangeFactor = 2.0
    /// The visible-change path needs the change to hold this long, in seconds, after motion stops.
    var visibleChangeHold = 1.5
    /// Frame-to-frame change below this counts as motion having stopped, for the
    /// visible-change path. Above `stillnessThreshold` because, from a phone propped low on
    /// the counter, steam rising past the rim never lets the box go fully still.
    var visibleCalmMotion = 0.08
    /// Share of the hold's frames in which a pixel must differ from the before-picture to
    /// count toward a visible change. Steam above the rim changes different pixels each
    /// frame and drops out; pasta ends sticking up out of the pot stay put.
    var visibleChangeSteadiness = 0.8
    /// A steady change over more than this share of the box is the view changing, not food:
    /// from a low counter angle the cook's body fills the space above the rim, and a bumped
    /// phone moves everything.
    var visibleChangeMaximum = 0.5
    /// A visit counts only when its hand spent at least `minimumDwell` over the pot's
    /// opening: inside the pan box and at least this share of the box's width in from its
    /// left and right edges. Food goes in over the middle. A hand at the box's edges holds a
    /// handle, shakes the pan or rests on the counter beside it, and a still pattern Vision
    /// takes for a hand sits wherever it is. Visits whose hand position isn't known are
    /// judged as before.
    var openingInset = 0.1
    /// A brightness change is taken for lighting only when, with smooth shading taken out,
    /// less than this share of the box changed. A light, or the cook's shadow as they lean
    /// in and back, brightens or darkens whole areas smoothly; food landing while the light
    /// changed still changes the box's detail.
    var lightingStructureLimit = 0.04
    /// How far around each pixel, in patch pixels, shading is measured for
    /// `lightingStructureLimit`: about 2.5 cm from a phone on the counter.
    var shadingRadius = 4

    var changeRule: ChangeRule {
        ChangeRule(lumaThreshold: lumaThreshold, chromaThreshold: chromaThreshold)
    }

    /// The tuning for one recipe step. Some ingredients, like minced garlic, change only a
    /// little of the pan, so their step asks for less change. Only ingredients carried in
    /// the hand count a hand letting go, and only ones that stay in sight count a change
    /// seen without a hand.
    func applying(_ watch: AdditionWatch?) -> DetectorSettings {
        var effective = self
        if let minimum = watch?.minimumChange {
            effective.additionThreshold = min(additionThreshold, minimum)
        }
        effective.countRelease = countRelease && watch?.countsRelease == true
        effective.visibleIngredient = countVisibleChange && (watch?.minimumChange ?? 0) > 0
        return effective
    }
}

/// What the detector needs from one analyzed camera frame.
struct FrameObservation: Sendable {
    /// Capture time in seconds. Only differences between frames matter.
    var time: Double
    /// Whether a tracked hand is inside the hand zone around the pan.
    var handInZone: Bool
    /// How open the hand over the pan is, in palm lengths (about 1 for a fist, 1.8 for an
    /// open hand). Nil when it can't be measured, or when two hands are over the pan.
    var handOpenness: Double? = nil
    /// The pan region, sampled from this frame.
    var region: PanPatch
    /// Where the hand over the pan is, relative to the pan box: (0, 0) its top left, (1, 1)
    /// its bottom right, beyond that in the margin around it. The mean of the hands when
    /// there are several. Nil when no hand is over the pan or it isn't known.
    var handPoint: NormPoint? = nil
    /// How many counted hands are over the pan.
    var handsInZone = 0
}

/// The verdict after a hand visited the pan and left.
struct DetectorDecision: Identifiable, Sendable {
    enum Outcome: String, Sendable {
        case addition
        case noChange
        case lightingChange
        /// The hand stayed too long: stirring, not adding.
        case stirring
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
    /// How far the hand opened while over the pan, in palm lengths.
    let handOpened: Double
    /// True when the hand letting go is what made this an addition.
    let released: Bool
    /// False when the pan never stopped moving and the after-picture was taken at the time limit.
    let settledCleanly: Bool
    let before: PanPatch
    let after: PanPatch
    /// True when no counted hand visited and a change that held in the box made the decision.
    var changeAlone = false
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
    /// How far the hand has opened during the current or last visit, in palm lengths.
    private(set) var handOpened = 0.0
    /// Warm-up ran out of patience and learned the pan from a frame with a hand in view,
    /// so the before-picture may include it.
    private(set) var learnedWithHand = false

    private var isArmed = false
    private var history: [Snapshot] = []
    private var frozenBaseline: PanPatch?
    private var previous: PanPatch?
    private var lastTime: Double?
    private var warmUpStart: Double?
    /// The stillest frame of the last few seconds of warm-up, for when it gives up.
    private var stillestWarmUp: (snapshot: Snapshot, motion: Double)?
    private var lastActiveTime = 0.0
    private var settleStart = 0.0
    private var stillSince: Double?
    private var cooldownUntil = 0.0
    private var decisionCount = 0
    private var visitIsStirring = false
    private var stirQuietUntil = -Double.infinity
    private var recentOpenness: [Double] = []
    private var leastOpen: Double?
    /// When the current visit's hand first arrived.
    private var visitStart = 0.0
    /// Seconds the current visit's hand spent over the pot's opening (see `openingInset`).
    private var overOpening = 0.0
    /// Whether the current visit's hand position was ever known.
    private var handPlaceKnown = false
    /// Why the latest visit, or the latest change seen without a hand, didn't end in an addition.
    private(set) var lastMiss: NoOffer?
    /// Counts updates to `lastMiss`, so a watcher can tell a new miss from an old one.
    private(set) var misses = 0

    // The visible-change path.
    /// Calm frames from the last moment, for the before-picture once motion starts.
    private var calmFrames: [Snapshot] = []
    /// The pan just before motion with no counted hand began.
    private var sightBaseline: PanPatch?
    private var sightStart = 0.0
    private var sightLastMotion = 0.0
    private var sightCalmSince: Double?
    /// For each pixel, in how many calm frames since `sightCalmSince` it differed from `sightBaseline`.
    private var sightCounts: [Int] = []
    private var sightFrames = 0

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
        stillestWarmUp = nil
        learnedWithHand = false
        stillSince = nil
        dwell = 0
        motion = 0
        liveChange = 0
        visitIsStirring = false
        stirQuietUntil = -Double.infinity
        resetOpenness()
        clearSight()
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
            if let best = stillestWarmUp, best.snapshot.time >= t - Self.historyDuration, best.motion <= motion {
                // Keep the stiller, recent one.
            } else {
                stillestWarmUp = (Snapshot(time: t, patch: frame.region), motion)
            }
            if let first = history.first, let last = history.last,
               last.time - first.time >= settings.warmUpDuration || (impatient && !active) {
                phase = .watching
            } else if t - started >= settings.warmUpGiveUp {
                // A hand that never leaves, real or imagined, would hold warm-up forever.
                if history.isEmpty, let best = stillestWarmUp {
                    history = [best.snapshot]
                    learnedWithHand = true
                }
                phase = .watching
            }

        case .watching:
            if settings.visibleIngredient, let decision = watchForChange(frame) { return decision }
            if active {
                beginVisit(at: t)
                if phase == .handInPan { track(frame.handOpenness) }
            } else if still {
                remember(frame)
            }

        case .handInPan:
            if active {
                dwell += dt
                lastActiveTime = t
                track(frame.handOpenness)
                notePlace(frame, dt)
                // In dim light Vision drops the hand for frames at a time, so a long stir
                // reaches `maximumDwell` of counted time late or never; the visit's span from
                // the hand's arrival, gaps included, says stirring too.
                if dwell > settings.maximumDwell || t - visitStart > settings.maximumDwell { visitIsStirring = true }
            } else if t - lastActiveTime >= settings.exitHold {
                if visitIsStirring {
                    return stirred(frame)
                } else if dwell < settings.minimumDwell {
                    // A hand passing over on its way somewhere else. Not worth judging.
                    miss(.visitTooShort(dwell))
                    endVisit()
                } else if handPlaceKnown && overOpening < settings.minimumDwell {
                    // The hand held a handle, shook the pan or rested beside it: nothing went in.
                    miss(.handBesidePan)
                    endVisit()
                } else {
                    phase = .settling
                    settleStart = t
                    stillSince = nil
                }
            }

        case .settling:
            if active {
                phase = .handInPan
                lastActiveTime = t
                track(frame.handOpenness)
                notePlace(frame, dt)
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

    /// The visible-change path, for steps whose ingredient stays in sight: motion in the
    /// box with no counted hand, then a change that holds for `visibleChangeHold` once
    /// motion stops, is judged like a visit. It catches a pour whose hand Vision never
    /// trusted. Seen from a phone propped low on the counter, the box holds the side of the
    /// pot and the space just above its rim, so the change must sit on the same pixels the
    /// whole hold (steam drifts and drops out) and must not fill most of the box (the
    /// cook's body or a bumped phone).
    private mutating func watchForChange(_ frame: FrameObservation) -> DetectorDecision? {
        let t = frame.time
        let calm = !frame.handInZone && motion < settings.visibleCalmMotion
        guard let baseline = sightBaseline else {
            if calm {
                calmFrames.append(Snapshot(time: t, patch: frame.region))
                calmFrames.removeAll { $0.time < t - settings.baselineLag - 1 }
            } else if let oldest = calmFrames.first {
                // The median of the calm moment before, so steam caught in one frame drops out.
                let lagged = calmFrames.filter { $0.time <= t - settings.baselineLag }
                sightBaseline = Self.median((lagged.isEmpty ? [oldest] : lagged).map(\.patch))
                sightStart = t
                sightLastMotion = t
                sightCalmSince = nil
            }
            return nil
        }
        guard calm else {
            sightLastMotion = t
            sightCalmSince = nil
            return nil
        }
        guard let mask = frame.region.changedMask(from: baseline, rule: settings.changeRule) else {
            clearSight(keeping: frame)
            return nil
        }
        if sightCalmSince == nil || sightCounts.count != mask.count {
            sightCalmSince = t
            sightCounts = [Int](repeating: 0, count: mask.count)
            sightFrames = 0
        }
        sightFrames += 1
        for (index, changed) in mask.enumerated() where changed { sightCounts[index] += 1 }
        guard let calmSince = sightCalmSince, t - calmSince >= settings.visibleChangeHold else { return nil }

        let needed = settings.visibleChangeFactor * settings.additionThreshold
        let hits = Double(sightFrames) * settings.visibleChangeSteadiness
        let steady = Double(sightCounts.filter { Double($0) >= hits }.count) / Double(max(mask.count, 1))
        let moving = sightLastMotion - sightStart
        if moving > settings.maximumDwell {
            // Motion that long without a counted hand is stirring, not a pour.
            miss(.visitTooLong(moving))
        } else if steady < needed {
            miss(.changeTooSmall(changed: steady, needed: needed))
        } else if steady > settings.visibleChangeMaximum && !looksLikeLighting(frame.region, from: baseline) {
            miss(.viewChanged(steady))
        } else {
            frozenBaseline = baseline
            dwell = 0
            resetOpenness()
            return decide(frame, settledCleanly: true, changeAlone: true)
        }
        clearSight(keeping: frame)
        return nil
    }

    /// Forgets the visible-change path's progress, keeping `frame` as the latest calm one.
    private mutating func clearSight(keeping frame: FrameObservation? = nil) {
        sightBaseline = nil
        sightCalmSince = nil
        sightCounts = []
        sightFrames = 0
        calmFrames = frame.map { [Snapshot(time: $0.time, patch: $0.region)] } ?? []
    }

    /// Each pixel's median over `patches`. Ones of another size than the last are left out.
    private static func median(_ patches: [PanPatch]) -> PanPatch {
        guard let last = patches.last else { preconditionFailure("median of no pictures") }
        let same = patches.filter { $0.width == last.width && $0.height == last.height }
        guard same.count > 2 else { return last }
        func plane(_ values: KeyPath<PanPatch, [UInt8]>) -> [UInt8] {
            (0..<last.pixelCount).map { index in same.map { $0[keyPath: values][index] }.sorted()[same.count / 2] }
        }
        return PanPatch(width: last.width, height: last.height, luma: plane(\.luma), cb: plane(\.cb), cr: plane(\.cr))
    }

    private mutating func miss(_ reason: NoOffer) {
        lastMiss = reason
        misses += 1
    }

    /// The whole pan got evenly brighter or darker, as when a light switches, rather than
    /// food landing in part of it. Brightness alone can't tell food in a bright change from
    /// the light, so the box's structure must also have stayed: see `lightingStructureLimit`.
    private func looksLikeLighting(_ after: PanPatch, from before: PanPatch) -> Bool {
        let shift = after.medianLumaShift(from: before)
        return settings.lightingVeto && abs(shift) >= settings.lightingShiftThreshold
            && after.fractionShifted(by: shift, within: max(settings.lumaThreshold, abs(shift) / 2), from: before)
                >= Self.lightingEvenness
            && after.structureChange(from: before, rule: settings.changeRule, radius: settings.shadingRadius)
                < settings.lightingStructureLimit
    }

    /// Adds the frame's time to `overOpening` when the hand is over the pot's opening.
    private mutating func notePlace(_ frame: FrameObservation, _ dt: Double) {
        guard let point = frame.handPoint else { return }
        handPlaceKnown = true
        if point.x >= settings.openingInset && point.x <= 1 - settings.openingInset { overOpening += dt }
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
        visitStart = t
        overOpening = 0
        handPlaceKnown = false
        // A hand back right after stirring is still stirring.
        visitIsStirring = t < stirQuietUntil
        resetOpenness()
        phase = .handInPan
    }

    private mutating func endVisit() {
        frozenBaseline = nil
        dwell = 0
        visitIsStirring = false
        phase = .watching
    }

    private mutating func resetOpenness() {
        recentOpenness.removeAll()
        leastOpen = nil
        handOpened = 0
    }

    /// Follows how open the hand is, as the median of the last three readings so one bad
    /// frame can't fake a release, and keeps the largest opening since it was most closed.
    private mutating func track(_ openness: Double?) {
        guard let openness else { return }
        recentOpenness.append(openness)
        if recentOpenness.count > 3 { recentOpenness.removeFirst() }
        guard recentOpenness.count == 3 else { return }
        let smoothed = recentOpenness.sorted()[1]
        let least = min(leastOpen ?? smoothed, smoothed)
        leastOpen = least
        handOpened = max(handOpened, smoothed - least)
    }

    /// The hand stayed too long, so it was stirring. Nothing is judged, the pan as it
    /// looks now becomes the new normal, and a hand coming straight back is ignored too.
    private mutating func stirred(_ frame: FrameObservation) -> DetectorDecision {
        let before = frozenBaseline ?? frame.region
        decisionCount += 1
        let decision = DetectorDecision(
            id: decisionCount,
            time: frame.time,
            outcome: .stirring,
            changedFraction: frame.region.changedFraction(from: before, rule: settings.changeRule),
            additionThreshold: settings.additionThreshold,
            medianLumaShift: frame.region.medianLumaShift(from: before),
            dwell: dwell,
            handOpened: handOpened,
            released: false,
            settledCleanly: false,
            before: before,
            after: frame.region
        )
        stirQuietUntil = frame.time + settings.stirQuiet
        history = [Snapshot(time: frame.time, patch: frame.region)]
        miss(.visitTooLong(dwell))
        clearSight(keeping: frame)
        endVisit()
        return decision
    }

    private mutating func decide(_ frame: FrameObservation, settledCleanly: Bool, changeAlone: Bool = false) -> DetectorDecision? {
        guard let before = frozenBaseline else {
            endVisit()
            return nil
        }
        let after = frame.region
        let changed = after.changedFraction(from: before, rule: settings.changeRule)
        let shift = after.medianLumaShift(from: before)

        // A hand opening over the pan let go of something, even if the pot hides it.
        let released = settings.countRelease && handOpened >= settings.releaseThreshold
        let outcome: DetectorDecision.Outcome
        if released {
            outcome = .addition
        } else if looksLikeLighting(after, from: before) {
            outcome = .lightingChange
            miss(.lightingVeto(shift))
        } else if changed >= settings.additionThreshold {
            outcome = .addition
        } else {
            outcome = .noChange
            miss(.changeTooSmall(changed: changed, needed: settings.additionThreshold))
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
            handOpened: handOpened,
            released: released,
            settledCleanly: settledCleanly,
            before: before,
            after: after,
            changeAlone: changeAlone
        )

        // Whatever happened, the pan as it looks now is the new normal.
        frozenBaseline = nil
        visitIsStirring = false
        history = [Snapshot(time: frame.time, patch: after)]
        clearSight(keeping: frame)
        if outcome == .addition {
            phase = .cooldown
            cooldownUntil = frame.time + settings.cooldown
        } else {
            phase = .watching
        }
        return decision
    }
}
