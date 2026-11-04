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

    private static let names: [(VNHumanHandPoseObservation.JointName, HandReading.JointName)] = [
        (.wrist, .wrist),
        (.thumbCMC, .thumbCMC), (.thumbMP, .thumbMP), (.thumbIP, .thumbIP), (.thumbTip, .thumbTip),
        (.indexMCP, .indexMCP), (.indexPIP, .indexPIP), (.indexDIP, .indexDIP), (.indexTip, .indexTip),
        (.middleMCP, .middleMCP), (.middlePIP, .middlePIP), (.middleDIP, .middleDIP), (.middleTip, .middleTip),
        (.ringMCP, .ringMCP), (.ringPIP, .ringPIP), (.ringDIP, .ringDIP), (.ringTip, .ringTip),
        (.littleMCP, .littleMCP), (.littlePIP, .littlePIP), (.littleDIP, .littleDIP), (.littleTip, .littleTip),
    ]

    /// Everything Vision said about each hand it found: its confidence and every joint it
    /// placed, in normalized top-left image coordinates. Which ones count is decided in
    /// `HandReading`, so the practice replay can apply the same rules.
    func readings(in pixelBuffer: CVPixelBuffer) -> [HandReading] {
        // Frames arrive already rotated upright, so no orientation correction is needed.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let observations = request.results else { return [] }
        return observations.map { observation in
            let points = (try? observation.recognizedPoints(.all)) ?? [:]
            let joints = Self.names.compactMap { vision, name -> HandReading.Joint? in
                guard let point = points[vision], point.confidence > 0 else { return nil }
                // Vision puts the origin at the bottom-left; the rest of the app uses top-left.
                let location = NormPoint(x: Double(point.location.x), y: 1 - Double(point.location.y))
                return HandReading.Joint(name: name, point: location, confidence: Double(point.confidence))
            }
            return HandReading(confidence: Double(observation.confidence), joints: joints)
        }
    }
}
