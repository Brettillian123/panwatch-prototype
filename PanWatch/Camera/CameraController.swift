import AVFoundation

/// Whether the camera is usable, for the screen.
enum CameraStatus: Equatable, Sendable {
    case starting
    case running
    case denied
    case failed(String)
}

/// Owns the capture session: the wide camera at 720p, every frame handed to `analyzer`.
///
/// Session work happens on `sessionQueue`. Frames arrive on a separate queue so a slow
/// frame never holds up configuration.
final class CameraController: @unchecked Sendable {
    let analyzer = FrameAnalyzer()

    /// Called when the phone is turned to the other landscape side. The picture flips,
    /// so a pan box drawn before no longer covers the pan.
    var onRotationChanged: (@Sendable () -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "PanWatch.session")
    private let frameQueue = DispatchQueue(label: "PanWatch.frames", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var rotationAngle: CGFloat?

    /// Asks for camera permission if needed, then runs the session with the camera at
    /// `position`. Calling it again switches cameras.
    func start(position: AVCaptureDevice.Position) async -> CameraStatus {
        guard await Self.hasPermission() else { return .denied }
        return await onSessionQueue { () -> CameraStatus in
            let status = self.configure(position: position)
            if status == .running, !self.session.isRunning {
                self.session.startRunning()
            }
            return status
        }
    }

    /// Stops the camera, for cooking without it. `start` runs it again.
    func stop() async {
        await onSessionQueue {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Freezes exposure, white balance, and focus, so the picture of the pan only changes
    /// when the pan does. Auto exposure drifting as the cook moves is the biggest source
    /// of false alarms, and this removes it at the camera. Unlocking hands control back to auto.
    func setAdjustmentsLocked(_ locked: Bool) {
        sessionQueue.async {
            guard let device = self.input?.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if locked {
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
                if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            }
        }
    }

    private static func hasPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func onSessionQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume(returning: work()) }
        }
    }

    /// Runs on `sessionQueue`.
    private func configure(position: AVCaptureDevice.Position) -> CameraStatus {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return .failed("This iPhone has no \(position == .front ? "front" : "back") camera available.")
        }
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: device)
        } catch {
            return .failed(error.localizedDescription)
        }

        // Center Stage reframes the shot as people move, which would slide the pan out
        // from under its box.
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false

        session.beginConfiguration()
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input, session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            return .failed("The camera is in use by something else.")
        }
        session.addInput(newInput)
        input = newInput
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        if !session.outputs.contains(output) {
            // The camera's native format: the analyzer reads brightness straight from the
            // first plane, with no color conversion.
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(analyzer, queue: frameQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        session.commitConfiguration()
        guard session.outputs.contains(output) else { return .failed("The camera's frames can't be read.") }

        disableVideoHDR(on: device)
        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                // Mirror the front camera so the screen behaves like a mirror when you point at the pan.
                connection.isVideoMirrored = position == .front
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        }
        followRotation(of: device)
        return .running
    }

    /// HDR video re-maps brightness frame by frame, which reads as change where there is none.
    private func disableVideoHDR(on device: AVCaptureDevice) {
        guard device.activeFormat.isVideoHDRSupported, (try? device.lockForConfiguration()) != nil else { return }
        device.automaticallyAdjustsVideoHDREnabled = false
        device.isVideoHDREnabled = false
        device.unlockForConfiguration()
    }

    /// Keeps frames upright whichever way the phone is propped.
    private func followRotation(of device: AVCaptureDevice) {
        rotationObservation?.invalidate()
        rotationAngle = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        // Apply the current angle right now, before the session starts, so even the first
        // frames are upright. Later changes arrive on the main queue and are applied on ours.
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.new]
        ) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async { self?.applyRotation(angle) }
        }
    }

    /// Runs on `sessionQueue`.
    private func applyRotation(_ angle: CGFloat) {
        guard let connection = output.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        let previous = rotationAngle
        rotationAngle = angle
        connection.videoRotationAngle = angle
        if let previous, previous != angle {
            onRotationChanged?()
        }
    }
}
