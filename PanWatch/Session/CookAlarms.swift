import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Rings a cooking timer as a real alarm when it ends: on the Lock Screen, through silent
/// mode, and with the app closed. It uses AlarmKit on iOS 26 and later; on earlier
/// versions it does nothing and the in-app timer is all there is. The alarm is a countdown,
/// so until it rings the system shows the time left on the Lock Screen and in the Dynamic
/// Island, drawn by the PanWatchTimer widget extension.
@MainActor
final class CookAlarms {
    /// The cook allowed alarms. Asked once at launch, next to the microphone.
    private(set) var allowed = false

    func requestPermission() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            allowed = await Self.authorize()
        }
        #endif
    }

    /// Sets the alarm for a timer, using the timer's id so it can be cancelled later.
    func schedule(id: UUID, label: String, at end: Date) {
        #if canImport(AlarmKit)
        guard allowed else { return }
        if #available(iOS 26.0, *) {
            Task { await Self.schedule(id: id, label: label, at: end) }
        }
        #endif
    }

    /// Called when the cook removes a timer, so its alarm never rings.
    func cancel(id: UUID) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: id)
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
extension CookAlarms {
    nonisolated private static func authorize() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .notDetermined:
            let state = try? await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        default:
            return false
        }
    }

    /// A countdown for the seconds left until `end`, with no schedule: AlarmKit counts it
    /// down on the Lock Screen and rings the alert when it reaches zero. There is no pause
    /// button, because the in-app timer can't pause either.
    nonisolated private static func schedule(id: UUID, label: String, at end: Date) async {
        let secondsLeft = max(1, end.timeIntervalSinceNow.rounded())
        let stop = AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
        let alert = AlarmPresentation.Alert(title: "\(label) timer is done", stopButton: stop)
        let countdown = AlarmPresentation.Countdown(title: "\(label)")
        let attributes = AlarmAttributes<CookAlarmData>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown),
            metadata: CookAlarmData(label: label),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<CookAlarmData>(
            countdownDuration: Alarm.CountdownDuration(preAlert: secondsLeft, postAlert: nil),
            schedule: nil,
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}
#endif
