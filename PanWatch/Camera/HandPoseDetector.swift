import CoreVideo
import Vision

/// Finds up to two hands per frame with Apple's built-in hand-pose model.
/// No training and nothing to download: it ships with iOS.
final class HandPoseDetector {
    private let request: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        return request
    }()

    private static let tipNames: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]

    /// Each hand found: its confident joints in normalized top-left image coordinates,
    /// and how open it is.
    func hands(in pixelBuffer: CVPixelBuffer) -> [TrackedHand] {
        // Frames arrive already rotated upright, so no orientation correction is needed.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }
        let height = Double(CVPixelBufferGetHeight(pixelBuffer))
        let aspect = height > 0 ? Double(CVPixelBufferGetWidth(pixelBuffer)) / height : 1
        return observations.compactMap { observation -> TrackedHand? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            // Vision puts the origin at the bottom-left; the rest of the app uses top-left.
            func confident(_ point: VNRecognizedPoint?) -> NormPoint? {
                guard let point, point.confidence >= 0.3 else { return nil }
                return NormPoint(x: Double(point.location.x), y: 1 - Double(point.location.y))
            }
            let joints = points.values.compactMap(confident)
            // A real hand shows several joints. One or two stray points are usually noise.
            guard joints.count >= 4 else { return nil }
            let openness = HandGeometry.openness(
                wrist: confident(points[.wrist]),
                palm: confident(points[.middleMCP]),
                tips: Self.tipNames.compactMap { confident(points[$0]) },
                aspect: aspect
            )
            return TrackedHand(joints: joints, openness: openness)
        }
    }
}
