import Testing
@testable import PanWatchCore

@Suite("Pan patch")
struct PanPatchTests {
    /// Runs `body` on a synthetic 1280 x 720 camera frame whose left half is dark and
    /// neutral and whose right half is bright and colored. Rows are padded, as real
    /// camera buffers often are, to check that sampling honors bytes-per-row.
    private func withTwoToneFrame<T>(_ body: (YCbCrPlanes) -> T) -> T {
        let width = 1280, height = 720, lumaStride = width + 64
        var luma = [UInt8](repeating: 0, count: lumaStride * height)
        for y in 0..<height {
            for x in 0..<width { luma[y * lumaStride + x] = x < width / 2 ? 50 : 200 }
        }
        let chromaWidth = width / 2, chromaHeight = height / 2, chromaStride = chromaWidth * 2 + 32
        var chroma = [UInt8](repeating: 0, count: chromaStride * chromaHeight)
        for y in 0..<chromaHeight {
            for x in 0..<chromaWidth {
                let left = x < chromaWidth / 2
                chroma[y * chromaStride + x * 2] = left ? 128 : 90
                chroma[y * chromaStride + x * 2 + 1] = left ? 128 : 170
            }
        }
        return luma.withUnsafeBufferPointer { lumaBuffer in
            chroma.withUnsafeBufferPointer { chromaBuffer in
                body(YCbCrPlanes(
                    luma: lumaBuffer.baseAddress!, lumaWidth: width, lumaHeight: height, lumaBytesPerRow: lumaStride,
                    chroma: chromaBuffer.baseAddress!, chromaWidth: chromaWidth, chromaHeight: chromaHeight,
                    chromaBytesPerRow: chromaStride
                ))
            }
        }
    }

    @Test func samplesOnlyTheRequestedRegion() {
        let right = withTwoToneFrame {
            PanPatch.sample($0, rect: NormRect(x: 0.55, y: 0.1, width: 0.4, height: 0.8), width: 16, height: 16)
        }
        #expect(right.luma.allSatisfy { $0 == 200 })
        #expect(right.cb.allSatisfy { $0 == 90 })
        #expect(right.cr.allSatisfy { $0 == 170 })

        let left = withTwoToneFrame {
            PanPatch.sample($0, rect: NormRect(x: 0.05, y: 0.1, width: 0.4, height: 0.8), width: 16, height: 16)
        }
        #expect(left.luma.allSatisfy { $0 == 50 })
        #expect(left.cb.allSatisfy { $0 == 128 })
    }

    @Test func aRegionAcrossTheSeamSeesBothHalves() {
        let middle = withTwoToneFrame {
            PanPatch.sample($0, rect: NormRect(x: 0.25, y: 0, width: 0.5, height: 1), width: 16, height: 8)
        }
        #expect(middle.luma[0] == 50)
        #expect(middle.luma[15] == 200)
    }

    @Test func sizeKeepsTheRegionsShape() {
        let wide = PanPatch.size(for: NormRect(x: 0, y: 0, width: 0.5, height: 0.5), frameWidth: 1280, frameHeight: 720)
        #expect(wide.width == 64 && wide.height == 36)
        let tall = PanPatch.size(for: NormRect(x: 0, y: 0, width: 0.1, height: 0.9), frameWidth: 1280, frameHeight: 720)
        #expect(tall.height == 64 && tall.width == 13)
    }

    @Test func countsChangedPixels() {
        let rule = DetectorSettings().changeRule
        #expect(Pans.withPasta.changedFraction(from: Pans.empty, rule: rule) == 0.25)
        #expect(Pans.empty.changedFraction(from: Pans.empty, rule: rule) == 0)
        #expect(Pans.withPasta.changedMask(from: Pans.empty, rule: rule)?.filter { $0 }.count == 256)
    }

    @Test func colorAloneCountsAsChange() {
        let rule = DetectorSettings().changeRule
        // Same brightness, noticeably yellower: pale pasta on a pale steel pan.
        let tinted = Pans.empty.painting(x: 0..<32, y: 0..<8, luma: 60, cb: 100, cr: 140)
        #expect(tinted.changedFraction(from: Pans.empty, rule: rule) == 0.25)
    }

    @Test func smallDifferencesAreNoise() {
        let rule = DetectorSettings().changeRule
        let noisy = Pans.empty.painting(x: 0..<32, y: 0..<32, luma: 70, cb: 133, cr: 124)
        #expect(noisy.changedFraction(from: Pans.empty, rule: rule) == 0)
    }

    @Test func mismatchedSizesCompareAsUnchanged() {
        let small = PanPatch(width: 8, height: 8, luma: 255)
        #expect(small.changedFraction(from: Pans.empty, rule: DetectorSettings().changeRule) == 0)
        #expect(small.changedMask(from: Pans.empty, rule: DetectorSettings().changeRule) == nil)
    }

    @Test func medianShiftSeparatesLightingFromFood() {
        #expect(Pans.brighter.medianLumaShift(from: Pans.empty) == 40)
        #expect(Pans.withPasta.medianLumaShift(from: Pans.empty) == 0)
    }

    @Test func evenShiftSeparatesLightingFromABigPour() {
        // Every pixel of the lit pan moved by 40.
        #expect(Pans.brighter.fractionShifted(by: 40, within: 24, from: Pans.empty) == 1)
        // The pour moved the median by 140, but only the covered three quarters moved.
        #expect(Pans.mostlyCovered.medianLumaShift(from: Pans.empty) == 140)
        #expect(Pans.mostlyCovered.fractionShifted(by: 140, within: 70, from: Pans.empty) == 0.75)
        let small = PanPatch(width: 8, height: 8, luma: 255)
        #expect(small.fractionShifted(by: 0, within: 24, from: Pans.empty) == 0)
    }
}

@Suite("Geometry")
struct GeometryTests {
    @Test func cornersInAnyOrderMakeTheSameRect() {
        let a = NormRect(corner: NormPoint(x: 0.7, y: 0.8), to: NormPoint(x: 0.2, y: 0.3))
        let b = NormRect(corner: NormPoint(x: 0.2, y: 0.3), to: NormPoint(x: 0.7, y: 0.8))
        #expect(a == b)
        #expect(a.x == 0.2 && a.y == 0.3)
        #expect(abs(a.width - 0.5) < 1e-9 && abs(a.height - 0.5) < 1e-9)
    }

    @Test func expandingStopsAtTheFrameEdge() {
        let grown = NormRect(x: 0.05, y: 0.5, width: 0.2, height: 0.2).expanded(by: 0.5)
        #expect(grown.minX == 0)
        #expect(abs(grown.maxX - 0.35) < 1e-9)
        #expect(abs(grown.minY - 0.4) < 1e-9)
    }

    @Test func tinyBoxesGrowAndStayInFrame() {
        let box = NormRect(x: 0.98, y: 0.5, width: 0.01, height: 0.01).atLeast(0.1)
        #expect(abs(box.width - 0.1) < 1e-9)
        #expect(abs(box.maxX - 1) < 1e-9)
    }

    @Test func handMustReachIntoTheZone() {
        let zone = NormRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let outside = [[NormPoint(x: 0.1, y: 0.1), NormPoint(x: 0.2, y: 0.2)]]
        let reaching = [[NormPoint(x: 0.1, y: 0.1), NormPoint(x: 0.45, y: 0.5)]]
        #expect(!HandGeometry.anyHand(outside, in: zone))
        #expect(HandGeometry.anyHand(reaching, in: zone))
        #expect(!HandGeometry.anyHand(reaching, in: zone, minimumJoints: 2))
    }
}

@Suite("Demo recipe")
struct RecipeTests {
    @Test func watchesOnlyTheAddSteps() {
        let watched = Recipe.garlicButterPasta.steps.filter { $0.watch != nil }.map(\.id)
        #expect(watched == [2, 4])
    }
}
