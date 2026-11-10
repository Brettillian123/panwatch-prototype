import Foundation

/// When the camera runs and detection judges: only while cook mode is on screen. Leaving it
/// (close, or a menu opened by voice mid-cook) stops the camera and pauses detection; timers
/// keep running. The pan box is kept, and detection resumes with it on the way back.
enum CameraGate {
    /// Cook mode is showing: the cook screen itself, or the help sheet opened over it.
    static func cookShowing(screen: AppScreen, helpFrom: AppScreen) -> Bool {
        screen == .cook || (screen == .help && helpFrom == .cook)
    }

    /// The camera should be running: cook mode is showing and the cook hasn't turned it off.
    static func cameraRuns(screen: AppScreen, helpFrom: AppScreen, cameraOn: Bool) -> Bool {
        cameraOn && cookShowing(screen: screen, helpFrom: helpFrom)
    }

    /// Detection judges only with the camera running in cook mode, a pan box set and not
    /// being drawn, no offer waiting, on a watched step not yet done, and no setup check running.
    static func armed(
        screen: AppScreen, helpFrom: AppScreen, cameraOn: Bool, hasPan: Bool, drawing: Bool,
        offer: Bool, watchedStep: Bool, stepFinished: Bool, setupRunning: Bool
    ) -> Bool {
        cameraRuns(screen: screen, helpFrom: helpFrom, cameraOn: cameraOn)
            && hasPan && !drawing && !offer && watchedStep && !stepFinished && !setupRunning
    }

    /// A turn of the phone drops the pan box only while the camera is live in cook mode. With
    /// the camera stopped on another screen no frame is read, so a turn there says nothing
    /// about the pot, and the box comes back with cook mode.
    static func turnDropsPan(cameraLive: Bool, screen: AppScreen, helpFrom: AppScreen, hasPan: Bool) -> Bool {
        cameraLive && hasPan && cookShowing(screen: screen, helpFrom: helpFrom)
    }
}
