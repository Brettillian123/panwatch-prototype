import Foundation
#if canImport(AlarmKit)
import AlarmKit

/// The app data AlarmKit carries with each timer's alarm. The app writes it when it sets
/// the alarm, and the PanWatchTimer widget reads it to draw the Lock Screen countdown, so
/// this file is compiled into both targets.
@available(iOS 26.0, *)
struct CookAlarmData: AlarmMetadata {
    /// The timer's name, such as "Pasta". Optional so alarms set by older builds still decode.
    var label: String?
}
#endif
