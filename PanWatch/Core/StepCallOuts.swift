import Foundation

/// A later step to call out once a timer reaches its cue.
struct StepCallOut: Equatable, Sendable {
    let stepIndex: Int
    let timerID: UUID
    let at: Date
    /// Called out together with the timer's own "done".
    let atTimerEnd: Bool
}

enum StepCallOuts {
    /// The steps after `stepIndex` cued to `timer`, matched by its label. Cue times shrink
    /// with the timer, so a fast timer (seconds for minutes) cues in seconds too.
    static func cued(to timer: SavedTimer, in recipe: Recipe, after stepIndex: Int) -> [StepCallOut] {
        let minutes = recipe.steps.compactMap(\.watch).first { $0.timerLabel == timer.label }?.timerMinutes ?? 0
        let duration = timer.end.timeIntervalSince(timer.start)
        let scale = minutes > 0 ? duration / Double(minutes * 60) : 1
        return recipe.steps.indices.compactMap { index in
            guard index > stepIndex, let cue = recipe.steps[index].cue, cue.timerLabel == timer.label else { return nil }
            let atEnd = cue.secondsLeft <= 0
            let at = atEnd ? timer.end : timer.end.addingTimeInterval(-Double(cue.secondsLeft) * scale)
            return StepCallOut(stepIndex: index, timerID: timer.id, at: at, atTimerEnd: atEnd)
        }
    }

    /// Lines the call-outs up again from timers saved before the app closed, finished ones
    /// included. `upcoming` is what's still to come, earliest first; `catchUp` is the
    /// furthest step whose moment passed while the app was closed, if it's past `stepIndex`.
    static func resumed(
        from timers: [SavedTimer],
        in recipe: Recipe,
        at stepIndex: Int,
        now: Date
    ) -> (upcoming: [StepCallOut], catchUp: Int?) {
        let all = timers.flatMap { cued(to: $0, in: recipe, after: stepIndex) }
        // Every call-out is for a step after `stepIndex`, so any that passed is ahead of it.
        let passed = all.filter { $0.at <= now }.map(\.stepIndex).max()
        let current = passed ?? stepIndex
        let upcoming = all.filter { $0.at > now && $0.stepIndex > current }.sorted { $0.at < $1.at }
        return (upcoming, passed)
    }
}
