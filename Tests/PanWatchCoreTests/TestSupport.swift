@testable import PanWatchCore

/// A sequence of frames at 15 fps, the rate the app analyzes at.
struct Timeline {
    static let frameInterval = 1.0 / 15

    private(set) var frames: [FrameObservation] = []
    private var time = 0.0

    mutating func hold(_ seconds: Double, hand: Bool = false, patch: PanPatch) {
        hold(seconds, hand: hand) { _ in patch }
    }

    /// Appends `seconds` of frames; `patch` receives the frame's index within this stretch.
    mutating func hold(_ seconds: Double, hand: Bool = false, patch: (Int) -> PanPatch) {
        let count = Int((seconds / Self.frameInterval).rounded())
        for index in 0..<count {
            frames.append(FrameObservation(time: time, handInZone: hand, region: patch(index)))
            time += Self.frameInterval
        }
    }
}

/// Synthetic pictures of a pan, 32 x 32.
enum Pans {
    static let side = 32
    static let empty = PanPatch(width: side, height: side, luma: 60)
    /// The empty pan with a pale yellow clump covering the top-left quarter.
    static let withPasta = empty.painting(x: 0..<16, y: 0..<16, luma: 200, cb: 100, cr: 150)
    /// `withPasta` plus a second clump in the bottom-right quarter.
    static let withMore = withPasta.painting(x: 16..<32, y: 16..<32, luma: 180, cb: 150, cr: 110)
    /// The whole pan brighter, as when a hood light switches on.
    static let brighter = PanPatch(width: side, height: side, luma: 100)
    /// A big pour: pale pasta over the top three quarters of the pan.
    static let mostlyCovered = empty.painting(x: 0..<32, y: 0..<24, luma: 200, cb: 100, cr: 150)

    /// An arm reaching over the pan: a large blob that shifts every frame.
    static func arm(_ frame: Int) -> PanPatch {
        let left = (frame % 4) * 4
        return empty.painting(x: left..<(left + 20), y: 4..<28, luma: 170, cb: 115, cr: 145)
    }
}

extension PanPatch {
    func painting(x: Range<Int>, y: Range<Int>, luma newLuma: UInt8, cb newCb: UInt8 = 128, cr newCr: UInt8 = 128) -> PanPatch {
        var copy = self
        for row in y where row >= 0 && row < height {
            for column in x where column >= 0 && column < width {
                let index = row * width + column
                copy.luma[index] = newLuma
                copy.cb[index] = newCb
                copy.cr[index] = newCr
            }
        }
        return copy
    }
}

func decisions(for timeline: Timeline, settings: DetectorSettings = DetectorSettings(), armed: Bool = true) -> [DetectorDecision] {
    var detector = AdditionDetector(settings: settings)
    detector.setArmed(armed)
    return timeline.frames.compactMap { detector.process($0) }
}
