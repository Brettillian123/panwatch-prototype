import Foundation

/// A point in normalized image coordinates: (0, 0) is the top-left corner of the
/// camera frame and (1, 1) is the bottom-right.
struct NormPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// A rectangle in normalized image coordinates (see `NormPoint`).
struct NormRect: Equatable, Sendable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The rectangle spanned by two opposite corners, given in any order.
    init(corner a: NormPoint, to b: NormPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    init(center: NormPoint, width: Double, height: Double) {
        self.init(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var center: NormPoint { NormPoint(x: x + width / 2, y: y + height / 2) }

    func contains(_ point: NormPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    /// Grows every side by `fraction` of the rectangle's own size, clipped to the frame.
    func expanded(by fraction: Double) -> NormRect {
        NormRect(
            x: x - width * fraction,
            y: y - height * fraction,
            width: width * (1 + 2 * fraction),
            height: height * (1 + 2 * fraction)
        ).clippedToFrame()
    }

    /// The part of the rectangle that lies inside the frame.
    func clippedToFrame() -> NormRect {
        let x0 = min(max(minX, 0), 1)
        let x1 = min(max(maxX, 0), 1)
        let y0 = min(max(minY, 0), 1)
        let y1 = min(max(maxY, 0), 1)
        return NormRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Grows the rectangle around its center to at least `minimumSide` on each side,
    /// then slides it back inside the frame.
    func atLeast(_ minimumSide: Double) -> NormRect {
        let w = min(1, max(width, minimumSide))
        let h = min(1, max(height, minimumSide))
        var result = NormRect(center: center, width: w, height: h)
        result.x = min(max(result.x, 0), 1 - w)
        result.y = min(max(result.y, 0), 1 - h)
        return result
    }
}

enum HandGeometry {
    /// Whether any detected hand has at least `minimumJoints` joints inside `zone`.
    static func anyHand(_ hands: [[NormPoint]], in zone: NormRect, minimumJoints: Int = 1) -> Bool {
        hands.contains { joints in
            joints.filter { zone.contains($0) }.count >= minimumJoints
        }
    }

    /// How open a hand is: the average distance from the wrist to the fingertips, in palm
    /// lengths (wrist to the base of the middle finger). About 1 for a fist or a hand
    /// closed around food, about 1.8 for an open hand. `aspect` is the frame's width over
    /// its height, so distances are measured in pixels rather than stretched coordinates.
    /// Nil without the wrist, the palm, and at least three fingertips.
    static func openness(wrist: NormPoint?, palm: NormPoint?, tips: [NormPoint], aspect: Double) -> Double? {
        guard let wrist, let palm, tips.count >= 3 else { return nil }
        func distance(_ a: NormPoint, _ b: NormPoint) -> Double {
            let dx = (a.x - b.x) * aspect
            let dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }
        let palmLength = distance(wrist, palm)
        guard palmLength > 0.005 else { return nil }
        let reach = tips.map { distance(wrist, $0) }.reduce(0, +) / Double(tips.count)
        return reach / palmLength
    }
}

/// A hand found in one frame.
struct TrackedHand: Sendable {
    /// Its confident joints.
    var joints: [NormPoint]
    /// See `HandGeometry.openness`.
    var openness: Double?
}
