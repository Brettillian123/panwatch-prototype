import Foundation

// AI confirm: the rules propose, Apple's on-device model confirms. This file is the
// platform-free half: the looser rules that propose candidates, the few frames a check
// sends, and the gate that turns candidates and answers into offers. The model call itself
// lives in the app (`AddChecker`), behind iOS 27. Without the model the gate passes
// today's rules straight through, so nothing changes.

extension DetectorSettings {
    /// "Any change at all" for the candidate rules. Not zero, so the visible-change path
    /// still has a size to scale from.
    static let candidateAnyChange = 0.001

    /// The looser tuning that proposes candidates: any hand visit over the middle of the pot
    /// that leaves (food that sinks below the rim changes nothing the camera sees), any hand
    /// opening over it, and a visible change half the size today's rules need.
    var candidateRules: DetectorSettings {
        var loose = self
        loose.minimumDwell = min(minimumDwell, 0.25)
        loose.additionThreshold = Self.candidateAnyChange
        loose.countRelease = true
        loose.releaseThreshold = min(releaseThreshold, 0.25)
        loose.visibleIngredient = countVisibleChange
        let visibleNeed = max(visibleChangeFactor * additionThreshold / 2, 0.02)
        loose.visibleChangeFactor = visibleNeed / Self.candidateAnyChange
        loose.cooldown = min(cooldown, 1.5)
        return loose
    }

    /// The change a visit too short or beside the pan needs to still be a candidate.
    var candidateShortVisitChange: Double { max(additionThreshold / 2, 0.01) }
}

/// The few frames a check sends, picked while a hand is over the pot: the hand arriving,
/// the moment it let go (or its lowest point), the hand leaving, and the pot after.
/// Generic over the picture type so the app can hold `CGImage`s and the tests anything.
struct Keyframes<Image> {
    enum Moment: String, Sendable, CaseIterable {
        case arriving, release, leaving, after
    }

    struct Frame {
        let moment: Moment
        let time: Double
        let image: Image
    }

    /// A hand back within this many seconds continues the same visit's frames.
    var episodeGap = 3.0
    /// Hand frames older than this when a check is made are left out.
    var freshness = 10.0
    /// The leaving frame is refreshed at most this often, to keep the crops cheap.
    var leavingInterval = 0.2

    private(set) var arriving: Frame?
    private(set) var release: Frame?
    private(set) var leaving: Frame?
    private var inVisit = false
    private var lastHandTime = -Double.infinity
    private var lowestY: Double?
    private var releaseSeen = false

    /// Every frame held; nothing is kept outside these slots.
    var held: [Frame] { [arriving, release, leaving].compactMap { $0 } }

    /// Feeds one analyzed frame. `capture` crops the current camera frame and is called at
    /// most once, only when a slot takes this frame. `handPoint` is relative to the pan box,
    /// y down, so a larger y is a hand lower toward the food.
    mutating func observe(time: Double, handInZone: Bool, handPoint: NormPoint?, released: Bool, capture: () -> Image?) {
        guard handInZone else {
            inVisit = false
            return
        }
        let starting = !inVisit
        inVisit = true
        if starting && time - lastHandTime > episodeGap { clear() }
        lastHandTime = time

        let wantsArriving = arriving == nil
        let wantsRelease: Bool
        if released && !releaseSeen {
            releaseSeen = true
            wantsRelease = true
        } else if !releaseSeen, !wantsArriving, let y = handPoint?.y, y > (lowestY ?? -Double.infinity) + 0.02 {
            lowestY = y
            wantsRelease = true
        } else {
            wantsRelease = false
        }
        let wantsLeaving = !wantsArriving && time - (leaving?.time ?? -Double.infinity) >= leavingInterval
        guard wantsArriving || wantsRelease || wantsLeaving, let image = capture() else { return }
        if wantsArriving {
            arriving = Frame(moment: .arriving, time: time, image: image)
            if let y = handPoint?.y { lowestY = y }
        }
        if wantsRelease { release = Frame(moment: .release, time: time, image: image) }
        if wantsLeaving { leaving = Frame(moment: .leaving, time: time, image: image) }
    }

    /// The frames for a check, in order and ending with the pot as it looks now, then
    /// forgets them all.
    mutating func take(at time: Double, after: Image?) -> [Frame] {
        var frames = held.filter { time - $0.time <= freshness }
        if let after { frames.append(Frame(moment: .after, time: time, image: after)) }
        clear()
        return frames
    }

    mutating func clear() {
        arriving = nil
        release = nil
        leaving = nil
        lowestY = nil
        releaseSeen = false
    }
}

/// What the on-device model said about one check.
struct AddVerdict: Equatable, Sendable {
    /// A hand is adding food or an ingredient into the pot.
    var adding: Bool
    /// What is going in, in a few words. Empty when nothing is.
    var food: String
    /// How sure, 0 to 1.
    var confidence: Double
}

/// Between the rules and the offer while the on-device check is on. Candidates and rules
/// offers become checks; only a confident "yes" offers. A timeout or an error falls back to
/// today's rules for that add, so it is never worse than the rules alone. Off, today's
/// rules pass straight through.
struct AddConfirmGate {
    struct Settings: Sendable {
        /// An offer needs at least this confidence in a "yes".
        var minimumConfidence = 0.6
        /// Seconds a check may take before the rules decide instead.
        var timeout = 3.0
        /// Candidates and rules offers this many seconds after a check's start join it
        /// rather than making a check of their own.
        var joinWindow = 4.0
    }

    struct Check: Sendable {
        let id: Int
        let step: Int
        /// When it was asked, on the frame clock.
        let time: Double
        /// "The recipe step says: ..."
        let context: String
        /// The decision an offer carries: today's rules' when they offered, else the candidate.
        var decision: DetectorDecision
        /// Today's rules offered for this add.
        var rulesOffered: Bool
        /// Later candidates that joined this check.
        var joined = 0
    }

    enum Resolution: String, Sendable {
        case confirmed, declined, unsure, timedOut, failed, stale

        /// The rules decide instead of the model.
        var fellBack: Bool { self == .timedOut || self == .failed }
    }

    /// How a check ended.
    struct Outcome: Sendable {
        let check: Check
        let resolution: Resolution
        let verdict: AddVerdict?
        /// The offer to make, if any.
        let offer: DetectorDecision?
    }

    /// What one frame's decisions led to.
    struct Step {
        /// An offer to make now.
        var offer: DetectorDecision?
        /// A new check to send to the model.
        var ask: Check?
        /// A check that just ended (here, only by timing out).
        var ended: Outcome?
    }

    /// What the model answered, if anything.
    enum Reply: Sendable {
        case verdict(AddVerdict)
        case failed
        case timedOut
    }

    var settings = Settings()
    /// Whether the on-device check is on.
    var checking = false
    private(set) var step = 0
    private(set) var pending: Check?
    /// The latest ended check, so a rules offer just after it joins it.
    private var ended: (check: Check, fellBack: Bool, offered: Bool)?
    private var checks = 0

    /// The recipe step changed: a pending check's answer is no longer wanted.
    mutating func setStep(_ newStep: Int) -> Outcome? {
        guard newStep != step else { return nil }
        step = newStep
        ended = nil
        guard let check = pending else { return nil }
        pending = nil
        return Outcome(check: check, resolution: .stale, verdict: nil, offer: nil)
    }

    /// Feeds one frame's decisions: today's rules' (any outcome) and the looser rules' candidate.
    mutating func receive(rules: DetectorDecision?, candidate: DetectorDecision?, at time: Double, context: String) -> Step {
        let rulesOffer = rules?.outcome == .addition ? rules : nil
        guard checking else { return Step(offer: rulesOffer) }
        var result = Step(ended: tick(at: time))
        if let offer = result.ended?.offer { result.offer = offer }
        guard let proposed = rulesOffer ?? candidate else { return result }

        if var check = pending {
            // Two candidates close together make one check.
            check.joined += 1
            if let rulesOffer {
                check.rulesOffered = true
                check.decision = rulesOffer
            }
            pending = check
        } else if let last = ended, time - last.check.time <= settings.joinWindow {
            // Part of an add already judged. If the model never answered, today's rules decide.
            if let rulesOffer, last.fellBack, !last.offered {
                ended?.offered = true
                result.offer = rulesOffer
            }
        } else {
            checks += 1
            let check = Check(id: checks, step: step, time: time, context: context, decision: proposed, rulesOffered: rulesOffer != nil)
            pending = check
            result.ask = check
        }
        return result
    }

    /// The model's reply to check `id`. Nil when the check already ended or went stale.
    mutating func answer(_ id: Int, _ reply: Reply) -> Outcome? {
        guard let check = pending, check.id == id, check.step == step else { return nil }
        let verdict: AddVerdict?
        let resolution: Resolution
        switch reply {
        case .verdict(let answer):
            verdict = answer
            resolution = !answer.adding ? .declined : answer.confidence >= settings.minimumConfidence ? .confirmed : .unsure
        case .failed:
            verdict = nil
            resolution = .failed
        case .timedOut:
            verdict = nil
            resolution = .timedOut
        }
        return end(check, resolution, verdict)
    }

    /// Ends a check that has waited longer than the timeout.
    mutating func tick(at time: Double) -> Outcome? {
        guard let check = pending, time - check.time > settings.timeout else { return nil }
        return end(check, .timedOut, nil)
    }

    private mutating func end(_ check: Check, _ resolution: Resolution, _ verdict: AddVerdict?) -> Outcome {
        let offer: DetectorDecision?
        switch resolution {
        case .confirmed: offer = check.decision
        case .timedOut, .failed: offer = check.rulesOffered ? check.decision : nil
        case .declined, .unsure, .stale: offer = nil
        }
        pending = nil
        ended = (check, resolution.fellBack, offer != nil)
        return Outcome(check: check, resolution: resolution, verdict: verdict, offer: offer)
    }
}

extension DetectorDecision {
    /// The decision as a candidate the model can turn into an offer. A visit long enough to
    /// be taken for stirring may have started with an add (pour, then stir), so it is asked
    /// about too; an offer always carries the `addition` outcome.
    var asCandidate: DetectorDecision {
        guard outcome != .addition else { return self }
        return DetectorDecision(
            id: id, time: time, outcome: .addition, changedFraction: changedFraction, additionThreshold: additionThreshold,
            medianLumaShift: medianLumaShift, dwell: dwell, handOpened: handOpened, released: released,
            settledCleanly: settledCleanly, before: before, after: after, changeAlone: changeAlone
        )
    }
}
