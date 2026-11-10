import Testing
@testable import PanWatchCore

@Suite("Camera only in cook mode")
struct CameraGateTests {
    @Test func cameraRunsOnlyWhileCookModeShows() {
        #expect(CameraGate.cameraRuns(screen: .cook, helpFrom: .cook, cameraOn: true))
        for screen in [AppScreen.recipes, .recipe, .voices, .makeVoice, .profile] {
            #expect(!CameraGate.cameraRuns(screen: screen, helpFrom: .cook, cameraOn: true))
        }
        #expect(!CameraGate.cameraRuns(screen: .cook, helpFrom: .cook, cameraOn: false))
    }

    @Test func helpOverCookKeepsTheCameraHelpElsewhereDoesNot() {
        #expect(CameraGate.cameraRuns(screen: .help, helpFrom: .cook, cameraOn: true))
        #expect(!CameraGate.cameraRuns(screen: .help, helpFrom: .voices, cameraOn: true))
        #expect(!CameraGate.cameraRuns(screen: .help, helpFrom: .recipes, cameraOn: true))
    }

    @Test func detectionPausesOffCookAndResumesWithTheSameBox() {
        func armed(_ screen: AppScreen) -> Bool {
            CameraGate.armed(
                screen: screen, helpFrom: .cook, cameraOn: true, hasPan: true, drawing: false,
                offer: false, watchedStep: true, stepFinished: false, setupRunning: false
            )
        }
        #expect(armed(.cook))
        #expect(!armed(.voices))
        #expect(!armed(.profile))
        // Back in cook mode with the box kept: judging again, no redraw needed.
        #expect(armed(.cook))
    }

    @Test func detectionNeedsABoxAWatchedStepAndNoOffer() {
        func armed(hasPan: Bool = true, drawing: Bool = false, offer: Bool = false, watched: Bool = true,
                   finished: Bool = false, setup: Bool = false) -> Bool {
            CameraGate.armed(
                screen: .cook, helpFrom: .cook, cameraOn: true, hasPan: hasPan, drawing: drawing,
                offer: offer, watchedStep: watched, stepFinished: finished, setupRunning: setup
            )
        }
        #expect(armed())
        #expect(!armed(hasPan: false))
        #expect(!armed(drawing: true))
        #expect(!armed(offer: true))
        #expect(!armed(watched: false))
        #expect(!armed(finished: true))
        #expect(!armed(setup: true))
    }

    @Test func aTurnOffCookModeKeepsTheBox() {
        // Held portrait on Voices mid-cook: the camera is stopped, the box stays.
        #expect(!CameraGate.turnDropsPan(cameraLive: false, screen: .voices, helpFrom: .cook, hasPan: true))
        // A stale turn arriving after the screen changed, before the camera stopped, still keeps it.
        #expect(!CameraGate.turnDropsPan(cameraLive: true, screen: .profile, helpFrom: .cook, hasPan: true))
        // In cook mode with the camera live, a turn means the phone moved.
        #expect(CameraGate.turnDropsPan(cameraLive: true, screen: .cook, helpFrom: .cook, hasPan: true))
        #expect(!CameraGate.turnDropsPan(cameraLive: true, screen: .cook, helpFrom: .cook, hasPan: false))
    }
}
