import CoreVideo

extension PanPatch {
    /// Samples `rect` from a bi-planar YCbCr camera frame. Returns nil for any other pixel format.
    static func sample(from pixelBuffer: CVPixelBuffer, rect: NormRect, longSide: Int = 128) -> PanPatch? {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return nil }

        let planes = YCbCrPlanes(
            luma: UnsafePointer(luma.assumingMemoryBound(to: UInt8.self)),
            lumaWidth: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0),
            lumaHeight: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0),
            lumaBytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0),
            chroma: UnsafePointer(chroma.assumingMemoryBound(to: UInt8.self)),
            chromaWidth: CVPixelBufferGetWidthOfPlane(pixelBuffer, 1),
            chromaHeight: CVPixelBufferGetHeightOfPlane(pixelBuffer, 1),
            chromaBytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        )
        let size = PanPatch.size(for: rect, frameWidth: planes.lumaWidth, frameHeight: planes.lumaHeight, longSide: longSide)
        return PanPatch.sample(planes, rect: rect, width: size.width, height: size.height)
    }
}
