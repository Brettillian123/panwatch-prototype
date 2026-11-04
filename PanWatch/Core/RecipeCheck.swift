import Foundation

extension Recipe {
    /// Mistakes that would make the recipe misbehave in the kitchen, in plain words.
    /// Empty means the recipe is fine. Every recipe in `Recipe.all` is checked by a test.
    func problems() -> [String] {
        var found: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            found.append("The recipe has no title.")
        }
        if steps.isEmpty {
            found.append("The recipe has no steps.")
        }
        // Timers started by earlier steps, with their length in seconds. A cue can only
        // wait on one of these, because the session schedules cues when a timer starts.
        var earlierTimers: [String: Int] = [:]
        for (index, step) in steps.enumerated() {
            let name = "Step \(step.id)"
            if step.id != index + 1 {
                found.append("\(name): ids must run 1, 2, 3 in order; expected \(index + 1).")
            }
            if step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append("\(name): the instruction is empty.")
            }
            if let cue = step.cue {
                if cue.secondsLeft < 0 {
                    found.append("\(name): the cue has negative time left.")
                }
                if let length = earlierTimers[cue.timerLabel] {
                    if cue.secondsLeft > length {
                        found.append("\(name): the cue waits for \(cue.secondsLeft) s left on \"\(cue.timerLabel)\", which only runs \(length) s.")
                    }
                } else {
                    found.append("\(name): the cue names timer \"\(cue.timerLabel)\", but no earlier step starts it.")
                }
            }
            if let watch = step.watch {
                if watch.timerMinutes <= 0 {
                    found.append("\(name): the timer must be at least 1 minute.")
                }
                if watch.ingredient.trimmingCharacters(in: .whitespaces).isEmpty
                    || watch.timerLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    found.append("\(name): the watch needs an ingredient and a timer name.")
                }
                if let change = watch.minimumChange, change < 0 || change > 1 {
                    found.append("\(name): the share of the pan that must change has to be between 0 and 1.")
                }
                earlierTimers[watch.timerLabel] = watch.timerMinutes * 60
            }
        }
        return found
    }
}
