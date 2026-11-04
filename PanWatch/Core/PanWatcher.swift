import Foundation

/// Why the camera hasn't offered anything lately, for the debug panel.
enum NoOffer: Equatable, Sendable {
    /// Why a hand Vision saw over the pan didn't count.
    enum HandMiss: Equatable, Sendable {
        case rejected(HandReading.Rejection)
        /// Seen in too few of the latest frames to trust yet.
        case flickering
        /// Held still so long it was taken for a pattern on the counter.
        case still
    }

    case handNotCounted(HandMiss)
    case visitTooShort(Double)
    case visitTooLong(Double)
    /// The hand stayed at the pan's edge or beside it, never over the opening.
    case handBesidePan
    case changeTooSmall(changed: Double, needed: Double)
    /// Most of the box changed at once: the view, not the food.
    case viewChanged(Double)
    case lightingVeto(Double)
    case settling

    var text: String {
        switch self {
        case .handNotCounted(.rejected(.lowConfidence(let confidence))):
            String(format: "No hand counted: Vision only %.0f%% sure it's a hand", confidence * 100)
        case .handNotCounted(.rejected(.fewJoints(let count))):
            "No hand counted: only \(count) joints clear"
        case .handNotCounted(.rejected(.noWrist)):
            "No hand counted: wrist hidden"
        case .handNotCounted(.flickering):
            "No hand counted: it flickered in and out"
        case .handNotCounted(.still):
            "No hand counted: it held still like a pattern"
        case .visitTooShort(let dwell):
            String(format: "Hand over the pan too briefly (%.1f s)", dwell)
        case .handBesidePan:
            "Hand stayed at the edge of the pan, never over it"
        case .visitTooLong(let dwell):
            String(format: "Moving over the pan too long (%.1f s), taken for stirring", dwell)
        case .changeTooSmall(let changed, let needed):
            String(format: "Pan changed too little (%.1f%% of %.1f%% needed)", changed * 100, needed * 100)
        case .viewChanged(let changed):
            String(format: "Most of the box changed (%.0f%%): the view, not food", changed * 100)
        case .lightingVeto(let shift):
            String(format: "Taken for a lighting change (brightness %+.0f)", shift)
        case .settling:
            "Still settling: waiting for the pan to stop moving"
        }
    }
}

/// The work done on every analyzed frame between Vision and the verdict: which hands
/// count, whether one is over the pan, and what the detector makes of it. The app and the
/// replay both run it, so a recording is judged the way the phone judges.
struct PanWatcher {
    struct Result: Sendable {
        /// Hands that pass the confidence and joint rules, counted or not.
        var seen: [TrackedHand] = []
        /// Hands the filter believes are real.
        var handsCounted = 0
        var handsIgnoredAsStill = 0
        var handInZone = false
        var handOpenness: Double?
        /// Where the hand over the pan is, relative to the pan box. See `FrameObservation.handPoint`.
        var handPoint: NormPoint?
        var decision: DetectorDecision?
        /// AI confirm: the looser rules' candidate for the on-device check, when one was proposed.
        var candidate: DetectorDecision?
    }

    var settings: DetectorSettings
    private(set) var detector: AdditionDetector
    private var handFilter: HandFilter
    private var region: NormRect?
    private var missesSeen = 0
    /// The latest reason nothing was offered. Nil after an addition.
    private(set) var noOffer: NoOffer?
    /// AI confirm: whether looser rules, run beside today's, propose candidates for the on-device check.
    var proposesCandidates = false
    /// AI confirm: the looser rules' detector. Today's `detector` is untouched by it.
    private(set) var candidateDetector = AdditionDetector()

    init(settings: DetectorSettings = DetectorSettings()) {
        self.settings = settings
        detector = AdditionDetector(settings: settings)
        handFilter = HandFilter(settings: settings)
    }

    /// Feeds one analyzed frame: what Vision read, the frame's width over its height, the
    /// pan box and its picture (nil until the pan is marked), and whether the step watches.
    mutating func process(
        time: Double, hands readings: [HandReading], aspect: Double,
        region newRegion: NormRect?, patch: PanPatch?, armed: Bool
    ) -> Result {
        if newRegion != region {
            region = newRegion
            detector.reset()
            candidateDetector.reset() // AI confirm
        }
        detector.settings = settings
        detector.setArmed(armed && newRegion != nil)
        handFilter.settings = settings

        let seen = readings.compactMap { $0.tracked(settings, aspect: aspect) }
        // Only hands that hold steady from frame to frame and move over seconds count.
        let filtered = handFilter.update(seen.map { HandGeometry.centroid($0.joints) }, at: time)
        let hands = filtered.counted.map { seen[$0] }
        var result = Result(seen: seen, handsCounted: hands.count, handsIgnoredAsStill: filtered.ignoredAsStill)

        if let newRegion, let patch {
            // Three joints, not one: a fingertip grazing the edge of the zone isn't a visit.
            let zone = newRegion.expanded(by: settings.handZoneMargin)
            let inZone = hands.filter { HandGeometry.anyHand([$0.joints], in: zone, minimumJoints: 3) }
            result.handInZone = !inZone.isEmpty
            // With two hands over the pan, there's no telling which one let go.
            result.handOpenness = inZone.count == 1 ? inZone[0].openness : nil
            if !inZone.isEmpty {
                let centers = inZone.map { HandGeometry.centroid($0.joints) }
                let x = centers.map(\.x).reduce(0, +) / Double(centers.count)
                let y = centers.map(\.y).reduce(0, +) / Double(centers.count)
                result.handPoint = NormPoint(
                    x: newRegion.width > 0 ? (x - newRegion.x) / newRegion.width : 0.5,
                    y: newRegion.height > 0 ? (y - newRegion.y) / newRegion.height : 0.5
                )
            }
            let frame = FrameObservation(
                time: time, handInZone: result.handInZone, handOpenness: result.handOpenness, region: patch,
                handPoint: result.handPoint, handsInZone: inZone.count
            )
            result.decision = detector.process(frame)
            // AI confirm: the looser rules, beside today's, propose candidates for the on-device check.
            candidateDetector.settings = settings.candidateRules
            candidateDetector.shortVisitChange = settings.candidateShortVisitChange
            candidateDetector.setArmed(proposesCandidates && armed)
            if proposesCandidates, let candidate = candidateDetector.process(frame),
               candidate.outcome == .addition || candidate.outcome == .stirring {
                // A visit long enough to be stirring may have started with an add: the model decides.
                result.candidate = candidate.asCandidate
            }
            noteWhy(result, readings: readings, zone: zone, ignoredAsStill: filtered.ignoredAsStill)
        }
        return result
    }

    private mutating func noteWhy(_ result: Result, readings: [HandReading], zone: NormRect, ignoredAsStill: Int) {
        if result.decision?.outcome == .addition {
            noOffer = nil
            missesSeen = detector.misses
        } else if detector.misses != missesSeen {
            missesSeen = detector.misses
            noOffer = detector.lastMiss
        } else if detector.phase == .settling {
            noOffer = .settling
        } else if detector.phase == .watching && !result.handInZone {
            // A hand Vision saw over the pan that didn't count, and why.
            let near = readings.filter { HandGeometry.anyHand([$0.joints.map(\.point)], in: zone, minimumJoints: 3) }
            let settings = settings
            if let rejection = near.lazy.compactMap({ $0.rejection(settings) }).first {
                noOffer = .handNotCounted(.rejected(rejection))
            } else if !near.isEmpty {
                noOffer = .handNotCounted(ignoredAsStill > 0 ? .still : .flickering)
            }
        }
    }
}
