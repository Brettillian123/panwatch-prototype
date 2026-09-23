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

    /// The confident joints of each hand found, in normalized top-left image coordinates.
    func hands(in pixelBuffer: CVPixelBuffer) -> [[NormPoint]] {
        // Frames arrive already rotated upright, so no orientation correction is needed.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }
        return observations.compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let joints = points.values
                .filter { $0.confidence >= 0.3 }
                // Vision puts the origin at the bottom-left; the rest of the app uses top-left.
                .map { NormPoint(x: Double($0.location.x), y: 1 - Double($0.location.y)) }
            // A real hand shows several joints. One or two stray points are usually noise.
            return joints.count >= 4 ? joints : nil
        }
    }
}
