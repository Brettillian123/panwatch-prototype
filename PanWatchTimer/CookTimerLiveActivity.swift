import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// The Live Activity the system shows while a cooking timer's alarm counts down. The
/// Lock Screen view is sized to be read from the stove, about a meter away.
struct CookTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<CookAlarmData>.self) { context in
            LockScreenTimer(name: timerName(context.attributes), state: context.state)
        } dynamicIsland: { context in
            let tint = context.attributes.tintColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(timerName(context.attributes))
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Sous Vision")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimeLeft(state: context.state)
                        .font(.system(size: 44, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(tint)
            } compactTrailing: {
                TimeLeft(state: context.state)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 64)
            } minimal: {
                TimeLeft(state: context.state)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 40)
            }
            .keylineTint(tint)
        }
    }
}

/// The timer's name as the cook said it, or "Timer" if an alarm carries none.
private func timerName(_ attributes: AlarmAttributes<CookAlarmData>) -> String {
    guard let label = attributes.metadata?.label, !label.isEmpty else { return "Timer" }
    return label
}

/// The Lock Screen banner: the timer's name and the app's, over the time left in figures
/// big enough to read across the kitchen.
private struct LockScreenTimer: View {
    let name: String
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("Sous Vision")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            TimeLeft(state: state)
                .font(.system(size: 64, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

/// The time left on the timer. While it counts down, the system ticks the figures itself,
/// so the view never needs an update from the app.
private struct TimeLeft: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown):
            let end = max(countdown.startDate, countdown.fireDate)
            Text(timerInterval: countdown.startDate...end, countsDown: true)
        case .paused(let paused):
            Text(Self.clock(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
        default:
            Text(Self.clock(0))
        }
    }

    /// "4:05" or "1:02:03", the way the system's own timer text reads.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
