import AVFoundation
import SwiftUI

/// Shows exactly the frames the analyzer measures, already rotated and mirrored, so the
/// box drawn on screen lines up with the pixels being compared.
struct CameraPreview: UIViewRepresentable {
    let analyzer: FrameAnalyzer

    func makeUIView(context: Context) -> SampleBufferView {
        let view = SampleBufferView()
        view.backgroundColor = .black
        view.displayLayer.videoGravity = .resizeAspect
        analyzer.attach(renderer: view.displayLayer.sampleBufferRenderer)
        return view
    }

    func updateUIView(_ uiView: SampleBufferView, context: Context) {}
}

final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        // layerClass guarantees the type.
        layer as! AVSampleBufferDisplayLayer
    }
}
