import AVFoundation

/// Setup check: locks exposure to a whole number of light pulses, so LED and fluorescent
/// lights can't roll bands across the pan (research 14, failure 4). Lights pulse at twice
/// the mains: 1/120 s on 60 Hz, 1/100 s on 50 Hz.
enum FlickerLock {
    private static let mainsKey = "flickerMains.v1"

    /// 50 or 60: what the setup check last found, or else what the region uses.
    static var mainsHertz: Int {
        let saved = UserDefaults.standard.integer(forKey: mainsKey)
        return saved == 50 || saved == 60 ? saved : MainsPower.hertz(region: Locale.current.region?.identifier)
    }

    /// The setup check saw flicker at the current setting, so the lights must run on the
    /// other mains frequency. The next lock uses it.
    static func switchMains() {
        UserDefaults.standard.set(MainsPower.other(mainsHertz), forKey: mainsKey)
    }

    /// Locks exposure; call with the device locked for configuration. Matched to the mains
    /// when the camera takes a custom exposure and ISO can keep the brightness; otherwise a
    /// plain lock at whatever auto exposure chose. Returns whether it was matched.
    @discardableResult
    static func lockExposure(_ device: AVCaptureDevice) -> Bool {
        if device.isExposureModeSupported(.custom) {
            let format = device.activeFormat
            let frame = device.activeVideoMaxFrameDuration.seconds
            let longest = min(format.maxExposureDuration.seconds, frame.isFinite && frame > 0 ? frame : 1.0 / 30)
            if let exposure = MainsPower.exposure(
                current: device.exposureDuration.seconds, iso: Double(device.iso), hertz: mainsHertz,
                shortest: format.minExposureDuration.seconds, longest: longest,
                minISO: Double(format.minISO), maxISO: Double(format.maxISO)
            ) {
                device.setExposureModeCustom(
                    duration: CMTime(seconds: exposure.duration, preferredTimescale: 1_000_000),
                    iso: Float(exposure.iso),
                    completionHandler: nil
                )
                return true
            }
        }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        return false
    }
}
