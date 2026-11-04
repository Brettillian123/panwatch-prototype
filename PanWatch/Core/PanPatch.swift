import Foundation

/// Read-only view of a 4:2:0 bi-planar YCbCr camera frame, the iPhone camera's native
/// format: a full-resolution brightness (luma) plane and a half-resolution plane of
/// interleaved Cb/Cr color pairs.
struct YCbCrPlanes {
    let luma: UnsafePointer<UInt8>
    let lumaWidth: Int
    let lumaHeight: Int
    let lumaBytesPerRow: Int
    let chroma: UnsafePointer<UInt8>
    /// Width in Cb/Cr pairs.
    let chromaWidth: Int
    let chromaHeight: Int
    let chromaBytesPerRow: Int
}

/// When a pixel counts as changed between two pictures of the pan.
struct ChangeRule: Equatable, Sendable {
    /// Brightness difference, 0-255.
    var lumaThreshold: Double
    /// Color difference, |ΔCb| + |ΔCr|. Catches pale pasta landing in a pale steel pan,
    /// where brightness alone barely moves.
    var chromaThreshold: Double
}

/// A small color thumbnail of the watched pan, kept in YCbCr so brightness and color
/// can be compared separately.
struct PanPatch: Equatable, Sendable {
    let width: Int
    let height: Int
    var luma: [UInt8]
    var cb: [UInt8]
    var cr: [UInt8]

    var pixelCount: Int { width * height }

    init(width: Int, height: Int, luma: [UInt8], cb: [UInt8], cr: [UInt8]) {
        precondition(
            luma.count == width * height && cb.count == luma.count && cr.count == luma.count,
            "PanPatch planes must match its size"
        )
        self.width = width
        self.height = height
        self.luma = luma
        self.cb = cb
        self.cr = cr
    }

    /// A patch filled with one color.
    init(width: Int, height: Int, luma: UInt8, cb: UInt8 = 128, cr: UInt8 = 128) {
        let count = width * height
        self.init(
            width: width,
            height: height,
            luma: [UInt8](repeating: luma, count: count),
            cb: [UInt8](repeating: cb, count: count),
            cr: [UInt8](repeating: cr, count: count)
        )
    }

    /// Patch dimensions for `rect` that keep the region's shape, with the long side
    /// at `longSide` pixels.
    static func size(for rect: NormRect, frameWidth: Int, frameHeight: Int, longSide: Int = 64) -> (width: Int, height: Int) {
        let pixelWidth = max(rect.width * Double(frameWidth), 1)
        let pixelHeight = max(rect.height * Double(frameHeight), 1)
        let aspect = pixelWidth / pixelHeight
        if aspect >= 1 {
            return (longSide, max(8, Int((Double(longSide) / aspect).rounded())))
        }
        return (max(8, Int((Double(longSide) * aspect).rounded())), longSide)
    }

    /// Samples `rect` from a camera frame into a `width` x `height` patch. Each output
    /// pixel averages a 3x3 grid of samples inside its cell, which suppresses sensor noise.
    static func sample(_ planes: YCbCrPlanes, rect: NormRect, width: Int, height: Int) -> PanPatch {
        precondition(width > 0 && height > 0, "PanPatch must have a size")
        let region = rect.clippedToFrame()
        let taps = 3

        // For each output index, `taps` evenly spaced source coordinates inside its cell.
        func positions(count: Int, start: Double, span: Double, limit: Int) -> [Int] {
            var result = [Int]()
            result.reserveCapacity(count * taps)
            let cell = span / Double(count)
            for index in 0..<count {
                for tap in 0..<taps {
                    let value = start + (Double(index) + (Double(tap) + 0.5) / Double(taps)) * cell
                    result.append(min(limit - 1, max(0, Int(value))))
                }
            }
            return result
        }

        let lumaX = positions(count: width, start: region.x * Double(planes.lumaWidth),
                              span: region.width * Double(planes.lumaWidth), limit: planes.lumaWidth)
        let lumaY = positions(count: height, start: region.y * Double(planes.lumaHeight),
                              span: region.height * Double(planes.lumaHeight), limit: planes.lumaHeight)
        let chromaX = positions(count: width, start: region.x * Double(planes.chromaWidth),
                                span: region.width * Double(planes.chromaWidth), limit: planes.chromaWidth)
        let chromaY = positions(count: height, start: region.y * Double(planes.chromaHeight),
                                span: region.height * Double(planes.chromaHeight), limit: planes.chromaHeight)

        let count = width * height
        var luma = [UInt8](repeating: 0, count: count)
        var cb = [UInt8](repeating: 0, count: count)
        var cr = [UInt8](repeating: 0, count: count)
        let samples = taps * taps

        for outY in 0..<height {
            for outX in 0..<width {
                var sumY = 0, sumCb = 0, sumCr = 0
                for tapY in 0..<taps {
                    let lumaRow = planes.luma + lumaY[outY * taps + tapY] * planes.lumaBytesPerRow
                    let chromaRow = planes.chroma + chromaY[outY * taps + tapY] * planes.chromaBytesPerRow
                    for tapX in 0..<taps {
                        sumY += Int(lumaRow[lumaX[outX * taps + tapX]])
                        let pair = chromaX[outX * taps + tapX] * 2
                        sumCb += Int(chromaRow[pair])
                        sumCr += Int(chromaRow[pair + 1])
                    }
                }
                let index = outY * width + outX
                luma[index] = UInt8(sumY / samples)
                cb[index] = UInt8(sumCb / samples)
                cr[index] = UInt8(sumCr / samples)
            }
        }
        return PanPatch(width: width, height: height, luma: luma, cb: cb, cr: cr)
    }

    /// Which pixels changed compared with `other`, or nil if the sizes differ.
    func changedMask(from other: PanPatch, rule: ChangeRule) -> [Bool]? {
        guard other.width == width, other.height == height else { return nil }
        let lumaLimit = Int(rule.lumaThreshold)
        let chromaLimit = Int(rule.chromaThreshold)
        var mask = [Bool](repeating: false, count: pixelCount)
        for i in 0..<pixelCount {
            let lumaDelta = abs(Int(luma[i]) - Int(other.luma[i]))
            let chromaDelta = abs(Int(cb[i]) - Int(other.cb[i])) + abs(Int(cr[i]) - Int(other.cr[i]))
            mask[i] = lumaDelta > lumaLimit || chromaDelta > chromaLimit
        }
        return mask
    }

    /// Fraction of pixels that changed compared with `other`; 0 if the sizes differ.
    func changedFraction(from other: PanPatch, rule: ChangeRule) -> Double {
        guard pixelCount > 0, let mask = changedMask(from: other, rule: rule) else { return 0 }
        return Double(mask.lazy.filter { $0 }.count) / Double(pixelCount)
    }

    /// Median signed brightness change compared with `other`. A light switching on moves
    /// every pixel the same way, so the median moves with it. An ingredient landing in part
    /// of the pan leaves most pixels alone, so the median stays near zero.
    func medianLumaShift(from other: PanPatch) -> Double {
        guard other.width == width, other.height == height, pixelCount > 0 else { return 0 }
        var histogram = [Int](repeating: 0, count: 511)
        for i in 0..<pixelCount {
            histogram[Int(luma[i]) - Int(other.luma[i]) + 255] += 1
        }
        let middle = (pixelCount + 1) / 2
        var seen = 0
        for (bin, count) in histogram.enumerated() {
            seen += count
            if seen >= middle { return Double(bin - 255) }
        }
        return 0
    }

    /// Fraction of pixels whose signed brightness change from `other` is within
    /// `tolerance` of `shift`; 0 if the sizes differ. A light switching on moves nearly
    /// every pixel by about the same amount. Food covering most of the pan also moves the
    /// median, but the part of the pan it didn't cover stays where it was.
    func fractionShifted(by shift: Double, within tolerance: Double, from other: PanPatch) -> Double {
        guard other.width == width, other.height == height, pixelCount > 0 else { return 0 }
        var near = 0
        for i in 0..<pixelCount where abs(Double(Int(luma[i]) - Int(other.luma[i])) - shift) <= tolerance {
            near += 1
        }
        return Double(near) / Double(pixelCount)
    }

    /// Which pixels changed in structure compared with `other`, or nil if the sizes differ.
    /// Shading is taken out first: `other`'s brightness is scaled, pixel by pixel, by how
    /// much brighter or darker the square of `radius` pixels around it got. A light
    /// switching on, or the cook's shadow moving as they lean in and back, brightens or
    /// darkens whole areas smoothly and drops out. Food, a splash or a hand changes the
    /// detail inside the square and stays. Color is compared as in `changedMask`.
    func structureMask(from other: PanPatch, rule: ChangeRule, radius: Int) -> [Bool]? {
        guard other.width == width, other.height == height, pixelCount > 0 else { return nil }
        let mine = boxSums(luma, radius: radius), theirs = boxSums(other.luma, radius: radius)
        let chromaLimit = Int(rule.chromaThreshold)
        var mask = [Bool](repeating: false, count: pixelCount)
        for i in 0..<pixelCount {
            let gain = min(max((mine[i] + 1) / (theirs[i] + 1), 0.25), 4)
            let lumaDelta = abs(Double(luma[i]) - gain * Double(other.luma[i]))
            let chromaDelta = abs(Int(cb[i]) - Int(other.cb[i])) + abs(Int(cr[i]) - Int(other.cr[i]))
            mask[i] = lumaDelta > rule.lumaThreshold || chromaDelta > chromaLimit
        }
        return mask
    }

    /// Fraction of pixels whose structure changed compared with `other`; 0 if the sizes differ.
    func structureChange(from other: PanPatch, rule: ChangeRule, radius: Int) -> Double {
        guard let mask = structureMask(from: other, rule: rule, radius: radius) else { return 0 }
        return Double(mask.lazy.filter { $0 }.count) / Double(pixelCount)
    }

    /// Each pixel's sum of `plane` over the square of `radius` around it, clipped at the edges.
    private func boxSums(_ plane: [UInt8], radius: Int) -> [Double] {
        var integral = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for r in 0..<height {
            var row = 0.0
            for c in 0..<width {
                row += Double(plane[r * width + c])
                integral[(r + 1) * (width + 1) + c + 1] = integral[r * (width + 1) + c + 1] + row
            }
        }
        var sums = [Double](repeating: 0, count: pixelCount)
        for r in 0..<height {
            let r0 = max(r - radius, 0), r1 = min(r + radius + 1, height)
            for c in 0..<width {
                let c0 = max(c - radius, 0), c1 = min(c + radius + 1, width)
                sums[r * width + c] = integral[r1 * (width + 1) + c1] - integral[r0 * (width + 1) + c1]
                    - integral[r1 * (width + 1) + c0] + integral[r0 * (width + 1) + c0]
            }
        }
        return sums
    }
}
