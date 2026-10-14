import Testing
@testable import PanWatchCore

@Suite("Recipe timing")
struct RecipeTimingTests {
    @Test func laterStepsWaitOnThePastaTimer() {
        let cues = Recipe.garlicButterPasta.steps.compactMap(\.cue)
        #expect(cues.allSatisfy { $0.timerLabel == "Pasta" })
        // Butter, then garlic, then draining, each with less time left than the one before.
        #expect(cues.map(\.secondsLeft) == [180, 90, 0])
    }

    @Test func theGarlicIsDoneBeforeThePasta() {
        let steps = Recipe.garlicButterPasta.steps
        let pasta = steps.compactMap(\.watch).first { $0.timerLabel == "Pasta" }
        let garlic = steps.first { $0.watch?.ingredient == "garlic" }
        let cue = garlic?.cue?.secondsLeft ?? 0
        #expect(cue >= (garlic?.watch?.timerMinutes ?? 0) * 60)
        #expect(cue < (pasta?.timerMinutes ?? 0) * 60)
    }

    @Test func everyStepNamesItsAmount() {
        for step in Recipe.garlicButterPasta.steps.dropLast() {
            #expect(step.instruction.contains { $0.isNumber }, "\(step.instruction)")
        }
    }
}
