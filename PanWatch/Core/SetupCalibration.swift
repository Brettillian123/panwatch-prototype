import Foundation

/// The setup check's arithmetic. From about two seconds of the pan with no hand in view it
/// measures the picture's own noise, the light, flicker, and contrast; from about three
/// seconds with the cook's hand over the pot it measures that hand. It returns detector
/// settings that fit this kitchen and plain findings about what's wrong with the setup
/// (research 14, calibration design).
enum SetupCalibration {
    /// One analyzed frame, as the camera hands it over.
    struct Frame: Sendable {
        var time: Double
        /// The pan box, or nil when there's no box.
        var patch: PanPatch?
        /// Every hand Vision reported, faint ones included.
        var hands: [HandReading]
    }

    /// Something about the setup, in the cook's words.
    enum Finding: Equatable, Sendable {
        case noPicture
        case tooDark
        case tooBright
        case handNotSeen
        case lowContrast
        case handSmall
        case restless
        case flicker
        case lookalike

        var title: String {
            switch self {
            case .noPicture: "Can't see the pot"
            case .tooDark: "It's dark"
            case .tooBright: "There's glare"
            case .handNotSeen: "Can't see your hand"
            case .lowContrast: "The pot is hard to see"
            case .handSmall: "The phone is far away"
            case .restless: "The phone is moving"
            case .flicker: "Your lights blink on camera"
            case .lookalike: "Something looks like a hand"
            }
        }

        /// The one thing to do about it.
        var fix: String {
            switch self {
            case .noPicture: "Point the phone at it and draw the box again."
            case .tooDark: "Turn on a light near the stove."
            case .tooBright: "Turn the phone away from bright light."
            case .handNotSeen: "Move the phone closer or add light."
            case .lowContrast: "Add light, or draw the box closer."
            case .handSmall: "Move it closer to the pot."
            case .restless: "Set it down where it can't move."
            case .flicker: "Nothing to do."
            case .lookalike: "Move it away if you can."
            }
        }

        /// The cook has something to do. The others are handled by the settings.
        var needsFix: Bool { self != .flicker && self != .lookalike }
    }

    /// What was measured. Brightness is 0-255; shares and changes are fractions of the box.
    struct Measurements: Equatable, Sendable {
        var stillFrames = 0
        var handFrames = 0
        /// A pixel's typical frame-to-frame brightness change while nothing moves (the 90th
        /// percentile over the box of each pixel's median change).
        var lumaNoise = 0.0
        /// The same for color, |ΔCb| + |ΔCr|.
        var chromaNoise = 0.0
        var meanLuma = 0.0
        /// Share of the box near black, and near white.
        var darkShare = 0.0
        var brightShare = 0.0
        /// Brightness beating from frame to frame or bands rolling across the box, as a
        /// fraction of the mean brightness.
        var flicker = 0.0
        /// Spread of brightness across the box (RMS contrast, 0-255).
        var contrast = 0.0
        /// Share of the box that changes between frames while nothing moves, and between
        /// frames a second apart, under the calibrated change rule.
        var stillChange = 0.0
        var settledChange = 0.0
        /// The surest "hand" Vision found while no hand was in view, if it kept finding one.
        var lookalikeConfidence: Double?
        /// Frames in which the cook's hand was usable, and its averages over them.
        var handSeenFrames = 0
        var handConfidence: Double?
        var handJoints: Double?
        /// The larger side of the hand's joints, as a fraction of the frame.
        var handSize: Double?
    }

    struct Result: Equatable, Sendable {
        var measurements: Measurements
        var tuning: SetupTuning
        /// Worst first.
        var findings: [Finding]

        /// The one fix to make, or nil when the setup is ready.
        var fix: Finding? { findings.first(where: \.needsFix) }
        var ready: Bool { fix == nil }
        /// What the check says at the end.
        var spoken: String {
            guard let fix else { return "Ready." }
            return "\(fix.title). \(fix.fix)"
        }
    }

    // The limits. Change thresholds sit three sigma above the picture's own noise; the hand
    // minimums at 70% of the cook's measured hand, never under the safety floors.
    static let sigmaMargin = 3.0
    static let handMargin = 0.7
    static let confidenceFloor = 0.3
    static let confidenceCeiling = 0.8
    static let jointFloor = 4
    static let darkLuma = 40.0
    static let nearBlack: UInt8 = 20
    static let nearWhite: UInt8 = 235
    static let darkShareLimit = 0.4
    static let glareShareLimit = 0.05
    static let flickerLimit = 0.02
    static let contrastLimit = 5.0
    static let restlessLimit = 0.10
    static let smallHand = 0.08
    static let minimumHandFrames = 3

    static func calibrate(still: [Frame], hand: [Frame], base: DetectorSettings) -> Result {
        var measured = Measurements()
        var findings: [Finding] = []
        var tuning = SetupTuning(base)

        // The still frames, all the size of the latest box.
        let size = still.last(where: { $0.patch != nil })?.patch.map { ($0.width, $0.height) }
        let patches = still.compactMap(\.patch).filter { $0.width == size?.0 && $0.height == size?.1 && $0.pixelCount > 0 }
        measured.stillFrames = patches.count
        if patches.count >= 4 {
            measurePicture(patches, base: base, into: &measured, tuning: &tuning)
            if measured.meanLuma < darkLuma || measured.darkShare > darkShareLimit { findings.append(.tooDark) }
            if measured.brightShare > glareShareLimit { findings.append(.tooBright) }
        } else {
            findings.append(.noPicture)
        }

        measureLookalikes(still, base: base, into: &measured)
        measureHand(hand, base: base, into: &measured)
        if measured.handSeenFrames < minimumHandFrames { findings.append(.handNotSeen) }
        tuneHand(measured, base: base, tuning: &tuning)

        if patches.count >= 4 {
            if measured.contrast < contrastLimit { findings.append(.lowContrast) }
        }
        if let size = measured.handSize, size < smallHand { findings.append(.handSmall) }
        if measured.stillChange > restlessLimit { findings.append(.restless) }
        if measured.flicker > flickerLimit { findings.append(.flicker) }
        if let lookalike = measured.lookalikeConfidence, lookalike >= base.handConfidence * handMargin {
            findings.append(.lookalike)
        }
        measured.handFrames = hand.count
        return Result(measurements: measured, tuning: tuning, findings: findings)
    }

    // MARK: The picture

    private static func measurePicture(_ patches: [PanPatch], base: DetectorSettings, into measured: inout Measurements, tuning: inout SetupTuning) {
        let width = patches[0].width
        let height = patches[0].height
        let pixels = patches[0].pixelCount
        let count = patches.count

        // Each pixel's median change from frame to frame. A median, so a hand that slips
        // through for a few frames doesn't count as noise.
        var lumaMedians = [Double](repeating: 0, count: pixels)
        var chromaMedians = [Double](repeating: 0, count: pixels)
        var lumaSteps = [Double](repeating: 0, count: count - 1)
        var chromaSteps = [Double](repeating: 0, count: count - 1)
        for p in 0..<pixels {
            for t in 1..<count {
                let now = patches[t], before = patches[t - 1]
                lumaSteps[t - 1] = Double(abs(Int(now.luma[p]) - Int(before.luma[p])))
                chromaSteps[t - 1] = Double(abs(Int(now.cb[p]) - Int(before.cb[p])) + abs(Int(now.cr[p]) - Int(before.cr[p])))
            }
            lumaMedians[p] = median(lumaSteps)
            chromaMedians[p] = median(chromaSteps)
        }
        measured.lumaNoise = percentile(lumaMedians, 0.9)
        measured.chromaNoise = percentile(chromaMedians, 0.9)

        // A half-normal change has its median at 0.674 sigma, so three sigma sits at 4.45
        // medians. Above the noise, never under the tuned values.
        let medianToThreeSigma = sigmaMargin / 0.674
        tuning.lumaThreshold = max(base.lumaThreshold, (measured.lumaNoise * medianToThreeSigma).rounded(.up))
        tuning.chromaThreshold = max(base.chromaThreshold, (measured.chromaNoise * medianToThreeSigma).rounded(.up))

        // How much of the box the noise still changes under that rule, frame to frame and a
        // second apart (the before and after pictures are about that far apart).
        let rule = ChangeRule(lumaThreshold: tuning.lumaThreshold, chromaThreshold: tuning.chromaThreshold)
        let steps = (1..<count).map { patches[$0].changedFraction(from: patches[$0 - 1], rule: rule) }
        let gap = max(1, count / 2)
        let spans = (gap..<count).map { patches[$0].changedFraction(from: patches[$0 - gap], rule: rule) }
        measured.stillChange = robustCeiling(steps)
        measured.settledChange = robustCeiling(spans)
        tuning.stillnessThreshold = max(base.stillnessThreshold, measured.stillChange)
        tuning.additionThreshold = max(base.additionThreshold, measured.settledChange, measured.stillChange)
        tuning.visibleCalmMotion = max(base.visibleCalmMotion, 2 * tuning.stillnessThreshold)

        // Light: the average picture.
        var average = [Double](repeating: 0, count: pixels)
        for patch in patches {
            for p in 0..<pixels { average[p] += Double(patch.luma[p]) }
        }
        for p in 0..<pixels { average[p] /= Double(count) }
        let mean = average.reduce(0, +) / Double(pixels)
        measured.meanLuma = mean
        measured.darkShare = Double(average.filter { $0 <= Double(nearBlack) }.count) / Double(pixels)
        measured.brightShare = Double(average.filter { $0 >= Double(nearWhite) }.count) / Double(pixels)
        measured.contrast = (average.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(pixels)).squareRoot()

        // Flicker: the whole box beating from frame to frame, or bands rolling across it
        // along rows or columns (which way depends on how the sensor sits).
        let means = patches.map { patch in Double(patch.luma.reduce(0) { $0 + Int($1) }) / Double(pixels) }
        let beats = (1..<count).map { means[$0] - means[$0 - 1] }
        let beat = robustRMS(beats) / 2.0.squareRoot()
        let rows = banding(patches, means: means, width: width, height: height, alongRows: true)
        let columns = banding(patches, means: means, width: width, height: height, alongRows: false)
        measured.flicker = mean > 0 ? max(beat, rows, columns) / mean : 0
    }

    /// The RMS of bands moving across the box between frames, in brightness. Bands are flat
    /// along a sensor line, so each line's average moves with them while the scene's own
    /// texture cancels out frame to frame. The pixel noise left in a line's average is
    /// measured from neighbors on the same line, where the bands cancel, and taken off.
    private static func banding(_ patches: [PanPatch], means: [Double], width: Int, height: Int, alongRows: Bool) -> Double {
        let lines = alongRows ? height : width
        let length = alongRows ? width : height
        guard lines > 1, length > 1 else { return 0 }
        func index(_ line: Int, _ along: Int) -> Int { alongRows ? line * width + along : along * width + line }

        var squares = 0.0
        var samples = 0
        var neighborDiffs: [Double] = []
        for t in 1..<patches.count {
            let now = patches[t], before = patches[t - 1]
            let global = means[t] - means[t - 1]
            for line in 0..<lines {
                var sum = 0.0
                var previous: Double?
                for along in 0..<length {
                    let i = index(line, along)
                    let step = Double(Int(now.luma[i]) - Int(before.luma[i]))
                    sum += step
                    if let previous { neighborDiffs.append(step - previous) }
                    previous = step
                }
                let moved = sum / Double(length) - global
                squares += moved * moved
                samples += 1
            }
        }
        guard samples > 0 else { return 0 }
        // A frame-to-frame step has twice a pixel's noise variance; neighbors' difference twice that.
        let pixelVariance = pow(robustSigma(neighborDiffs), 2) / 4
        let lineNoise = 2 * pixelVariance / Double(length)
        let moving = max(0, squares / Double(samples) - lineNoise)
        // A step between frames doubles the variance of the bands themselves.
        return (moving / 2).squareRoot()
    }

    // MARK: Hands

    /// The surest thing Vision called a hand while no hand was in view, if it found one in
    /// at least three frames. Wood grain and shiny bags do this.
    private static func measureLookalikes(_ still: [Frame], base: DetectorSettings, into measured: inout Measurements) {
        let best = still.compactMap { frame in frame.hands.map(\.confidence).max() }
        guard best.count >= minimumHandFrames else { return }
        measured.lookalikeConfidence = best.max()
    }

    /// The cook's hand: in each frame the surest hand, if Vision is sure enough of it to be
    /// usable at all.
    private static func measureHand(_ frames: [Frame], base: DetectorSettings, into measured: inout Measurements) {
        var confidences: [Double] = []
        var joints: [Double] = []
        var sizes: [Double] = []
        for frame in frames {
            guard let hand = frame.hands.max(by: { $0.confidence < $1.confidence }) else { continue }
            let confident = hand.confidentJoints(base)
            guard hand.confidence >= confidenceFloor, confident.count >= jointFloor else { continue }
            confidences.append(hand.confidence)
            joints.append(Double(confident.count))
            let xs = confident.map(\.point.x), ys = confident.map(\.point.y)
            sizes.append(max(xs.max()! - xs.min()!, ys.max()! - ys.min()!))
        }
        measured.handSeenFrames = confidences.count
        guard !confidences.isEmpty else { return }
        measured.handConfidence = confidences.reduce(0, +) / Double(confidences.count)
        measured.handJoints = joints.reduce(0, +) / Double(joints.count)
        measured.handSize = sizes.reduce(0, +) / Double(sizes.count)
    }

    /// A hand weaker here than the tuned minimums lowers them to 70% of it, never under the
    /// floors. Only something that looked like a hand while none was in view raises them,
    /// and only while the cook's own hand stays clearly above it.
    private static func tuneHand(_ measured: Measurements, base: DetectorSettings, tuning: inout SetupTuning) {
        var confidence = base.handConfidence
        var joints = base.minimumHandJoints
        if measured.handSeenFrames >= minimumHandFrames, let mean = measured.handConfidence, let meanJoints = measured.handJoints {
            confidence = min(confidence, handMargin * mean)
            joints = min(joints, Int((handMargin * meanJoints).rounded(.down)))
            if let lookalike = measured.lookalikeConfidence {
                let clear = lookalike + 0.05
                if clear <= 0.8 * mean { confidence = max(confidence, clear) }
            }
        }
        confidence = min(max(confidence, confidenceFloor), confidenceCeiling)
        joints = max(joints, jointFloor)
        tuning.handConfidence = confidence
        tuning.minimumHandJoints = joints
        // The holding path trades joints for certainty, so it moves with the open-hand one
        // and never asks for less than it.
        let shifted = base.holdingHandConfidence + (confidence - base.handConfidence)
        tuning.holdingHandConfidence = min(max(shifted, confidence), 0.9)
        tuning.holdingHandJoints = max(min(base.holdingHandJoints, joints), jointFloor)
    }

    // MARK: Statistics

    static func median(_ values: [Double]) -> Double { percentile(values, 0.5) }

    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = fraction * Double(sorted.count - 1)
        let low = Int(position.rounded(.down)), high = Int(position.rounded(.up))
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
    }

    /// Standard deviation from the median absolute deviation, so a few odd frames don't move it.
    static func robustSigma(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let center = median(values)
        return 1.4826 * median(values.map { abs($0 - center) })
    }

    /// Root mean square from the median square, so a hand passing for a few frames doesn't
    /// move it, while a beat that flips sign every frame still counts in full.
    static func robustRMS(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        // The median square of a normal value is 0.455 of its variance.
        return (median(values.map { $0 * $0 }) / 0.455).squareRoot()
    }

    /// The median plus three robust sigmas.
    static func robustCeiling(_ values: [Double]) -> Double {
        median(values) + sigmaMargin * robustSigma(values)
    }
}

/// What the setup check set for one pan box, laid over the cook's own tuning.
struct SetupTuning: Codable, Equatable, Sendable {
    var lumaThreshold: Double
    var chromaThreshold: Double
    var stillnessThreshold: Double
    var additionThreshold: Double
    var visibleCalmMotion: Double
    var handConfidence: Double
    var holdingHandConfidence: Double
    var minimumHandJoints: Int
    var holdingHandJoints: Int

    init(_ settings: DetectorSettings) {
        lumaThreshold = settings.lumaThreshold
        chromaThreshold = settings.chromaThreshold
        stillnessThreshold = settings.stillnessThreshold
        additionThreshold = settings.additionThreshold
        visibleCalmMotion = settings.visibleCalmMotion
        handConfidence = settings.handConfidence
        holdingHandConfidence = settings.holdingHandConfidence
        minimumHandJoints = settings.minimumHandJoints
        holdingHandJoints = settings.holdingHandJoints
    }

    /// The change thresholds only ever rise to the measured noise; the hand minimums are the
    /// measured ones.
    func applied(to settings: DetectorSettings) -> DetectorSettings {
        var tuned = settings
        tuned.lumaThreshold = max(settings.lumaThreshold, lumaThreshold)
        tuned.chromaThreshold = max(settings.chromaThreshold, chromaThreshold)
        tuned.stillnessThreshold = max(settings.stillnessThreshold, stillnessThreshold)
        tuned.additionThreshold = max(settings.additionThreshold, additionThreshold)
        tuned.visibleCalmMotion = max(settings.visibleCalmMotion, visibleCalmMotion)
        tuned.handConfidence = handConfidence
        tuned.holdingHandConfidence = holdingHandConfidence
        tuned.minimumHandJoints = minimumHandJoints
        tuned.holdingHandJoints = holdingHandJoints
        return tuned
    }
}

/// Mains power, for exposures that LED and fluorescent flicker can't band.
enum MainsPower {
    /// Regions on 60 Hz mains; everywhere else is taken as 50 Hz until the setup check
    /// measures otherwise.
    static let sixtyHertzRegions: Set<String> = [
        "US", "CA", "MX", "PR", "GU", "VI", "AS", "MP", "BS", "BZ", "CR", "CU", "DO", "SV", "GT", "HT", "HN",
        "NI", "PA", "TT", "CO", "EC", "PE", "VE", "BR", "SR", "KR", "TW", "PH", "SA", "LR", "FM", "MH", "PW",
    ]

    static func hertz(region: String?) -> Int {
        guard let region else { return 60 }
        return sixtyHertzRegions.contains(region.uppercased()) ? 60 : 50
    }

    static func other(_ hertz: Int) -> Int { hertz == 50 ? 60 : 50 }

    /// The exposure nearest the current one that lasts a whole number of light pulses
    /// (lights pulse at twice the mains), with ISO moved to keep the brightness. Nil when
    /// no such exposure fits the camera, or when ISO can't make up the difference within
    /// half a stop either way, since a blown-out or murky pan is worse than banding.
    static func exposure(
        current: Double, iso: Double, hertz: Int,
        shortest: Double, longest: Double, minISO: Double, maxISO: Double
    ) -> (duration: Double, iso: Double)? {
        let pulse = 1 / Double(2 * hertz)
        guard current > 0, iso > 0, hertz > 0, shortest <= pulse, longest >= pulse else { return nil }
        let most = max(1, Int((longest / pulse + 1e-9).rounded(.down)))
        let pulses = min(max(1, Int((current / pulse).rounded())), most)
        let duration = Double(pulses) * pulse
        let wanted = iso * current / duration
        let matched = min(max(wanted, minISO), maxISO)
        let brightness = matched / wanted
        guard brightness >= 1 / 1.5, brightness <= 1.5 else { return nil }
        return (duration, matched)
    }
}
