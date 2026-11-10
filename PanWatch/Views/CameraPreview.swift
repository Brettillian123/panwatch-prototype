import AVFoundation
import SwiftUI

/// Shows exactly the frames the analyzer measures, already rotated and mirrored, so the
/// box drawn on screen lines up with the pixels being compared.
struct CameraPreview: UIViewRepresentable {
    let analyzer: FrameAnalyzer
    /// Fill the view (cropping), or fit the whole picture in it.
    var fill = false

    func makeUIView(context: Context) -> SampleBufferView {
        let view = SampleBufferView()
        view.backgroundColor = .black
        view.displayLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        analyzer.attach(renderer: view.displayLayer.sampleBufferRenderer)
        return view
    }

    func updateUIView(_ uiView: SampleBufferView, context: Context) {
        let gravity: AVLayerVideoGravity = fill ? .resizeAspectFill : .resizeAspect
        if uiView.displayLayer.videoGravity != gravity { uiView.displayLayer.videoGravity = gravity }
    }
}

final class SampleBufferView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        // layerClass guarantees the type.
        layer as! AVSampleBufferDisplayLayer
    }
}
