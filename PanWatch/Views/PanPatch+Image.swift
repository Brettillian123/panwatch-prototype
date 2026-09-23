import CoreGraphics
import Foundation

extension PanPatch {
    /// An RGB picture of the patch. Pixels flagged in `highlight` are tinted orange.
    func cgImage(highlight: [Bool]? = nil) -> CGImage? {
        guard pixelCount > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: pixelCount * 4)
        for i in 0..<pixelCount {
            // Full-range BT.601, the camera's color encoding.
            let y = Double(luma[i])
            let u = Double(cb[i]) - 128
            let v = Double(cr[i]) - 128
            var red = y + 1.402 * v
            var green = y - 0.344136 * u - 0.714136 * v
            var blue = y + 1.772 * u
            if let highlight, i < highlight.count, highlight[i] {
                red = red * 0.3 + 255 * 0.7
                green = green * 0.3 + 149 * 0.7
                blue *= 0.3
            }
            rgba[i * 4] = Self.channel(red)
            rgba[i * 4 + 1] = Self.channel(green)
            rgba[i * 4 + 2] = Self.channel(blue)
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }
}
