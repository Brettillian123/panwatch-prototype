import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Rings a cooking timer as a real alarm when it ends: on the Lock Screen, through silent
/// mode, and with the app closed. It uses AlarmKit on iOS 26 and later; on earlier
/// versions it does nothing and the in-app timer is all there is. The alarm is a plain
/// alert at the end time, so no widget extension is needed; the countdown shows in the app.
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
/// AlarmKit wants app data attached to each alarm; a cooking timer needs none.
@available(iOS 26.0, *)
struct CookAlarmData: AlarmMetadata {}

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

    nonisolated private static func schedule(id: UUID, label: String, at end: Date) async {
        let stop = AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
        let alert = AlarmPresentation.Alert(title: "\(label) timer is done", stopButton: stop)
        let attributes = AlarmAttributes<CookAlarmData>(
            presentation: AlarmPresentation(alert: alert),
            metadata: CookAlarmData(),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration<CookAlarmData>(
            countdownDuration: nil,
            schedule: .fixed(end),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .default
        )
        _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}
#endif
