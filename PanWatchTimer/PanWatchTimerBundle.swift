import SwiftUI
import WidgetKit

/// The widget extension behind Sous Vision's timers on the Lock Screen and in the Dynamic
/// Island. AlarmKit runs each timer's countdown; this extension only draws it.
@main
struct PanWatchTimerBundle: WidgetBundle {
    var body: some Widget {
        CookTimerLiveActivity()
    }
}
