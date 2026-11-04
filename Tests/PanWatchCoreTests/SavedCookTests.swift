import Foundation
import Testing
@testable import PanWatchCore

@Suite("Saved cook")
struct SavedCookTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func cook(_ title: String = Recipe.garlicButterPasta.title, step: Int = 2, savedAgo: TimeInterval = 60) -> SavedCook {
        SavedCook(recipeTitle: title, stepIndex: step, finishedSteps: [1], savedAt: now.addingTimeInterval(-savedAgo))
    }

    @Test func roundTrip() {
        let saved = cook()
        #expect(SavedCook.decode(saved.encoded()) == saved)
    }

    @Test func damagedDataIsNil() {
        #expect(SavedCook.decode(Data("not json".utf8)) == nil)
        #expect(SavedCook.decode(Data()) == nil)
    }

    @Test func resumesARecentCook() {
        let recipe = cook().recipe(in: Recipe.all, at: now)
        #expect(recipe?.title == Recipe.garlicButterPasta.title)
    }

    @Test func expiresAfterSixHours() {
        #expect(cook(savedAgo: 6 * 60 * 60 - 1).recipe(in: Recipe.all, at: now) != nil)
        #expect(cook(savedAgo: 6 * 60 * 60).recipe(in: Recipe.all, at: now) == nil)
        #expect(cook(savedAgo: 2 * 24 * 60 * 60).recipe(in: Recipe.all, at: now) == nil)
    }

    @Test func unknownRecipeIsIgnored() {
        #expect(cook("Beef Wellington").recipe(in: Recipe.all, at: now) == nil)
    }

    @Test func missingStepIsIgnored() {
        #expect(cook(step: 40).recipe(in: Recipe.all, at: now) == nil)
        #expect(cook(step: -1).recipe(in: Recipe.all, at: now) == nil)
    }
}

@Suite("Step call-outs after a relaunch")
struct StepCallOutsTests {
    private let pasta = Recipe.garlicButterPasta
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// The pasta timer as the app starts it on step 2 (index 1): 9 minutes, or 9 seconds fast.
    private func pastaTimer(fast: Bool = false) -> SavedTimer {
        SavedTimer(id: UUID(), label: "Pasta", start: start, end: start.addingTimeInterval(fast ? 9 : 9 * 60))
    }

    @Test func cuesMatchTheTimerLabel() {
        let timer = pastaTimer()
        let callOuts = StepCallOuts.cued(to: timer, in: pasta, after: 1)
        #expect(callOuts.map(\.stepIndex) == [2, 3, 4])
        #expect(callOuts.map { timer.end.timeIntervalSince($0.at) } == [180, 90, 0])
        #expect(callOuts.map(\.atTimerEnd) == [false, false, true])
        #expect(callOuts.allSatisfy { $0.timerID == timer.id })
    }

    @Test func fastTimersCueInSeconds() {
        let timer = pastaTimer(fast: true)
        let callOuts = StepCallOuts.cued(to: timer, in: pasta, after: 1)
        let left = callOuts.map { timer.end.timeIntervalSince($0.at) }
        #expect(zip(left, [3, 1.5, 0]).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test func otherTimersCueNothing() {
        let garlic = SavedTimer(id: UUID(), label: "Garlic", start: start, end: start.addingTimeInterval(60))
        #expect(StepCallOuts.cued(to: garlic, in: pasta, after: 1).isEmpty)
    }

    @Test func onlyLaterStepsAreCued() {
        #expect(StepCallOuts.cued(to: pastaTimer(), in: pasta, after: 3).map(\.stepIndex) == [4])
    }

    @Test func relaunchBeforeAnyCueKeepsThemAll() {
        let resumed = StepCallOuts.resumed(from: [pastaTimer()], in: pasta, at: 1, now: start.addingTimeInterval(60))
        #expect(resumed.catchUp == nil)
        #expect(resumed.upcoming.map(\.stepIndex) == [2, 3, 4])
    }

    @Test func relaunchAfterACueCatchesUp() {
        // Seven minutes in, the butter (3 minutes left of 9) has passed; the garlic (90 seconds) hasn't.
        let resumed = StepCallOuts.resumed(from: [pastaTimer()], in: pasta, at: 1, now: start.addingTimeInterval(7 * 60))
        #expect(resumed.catchUp == 2)
        #expect(resumed.upcoming.map(\.stepIndex) == [3, 4])
    }

    @Test func relaunchAfterTheTimerEndedGoesToTheLastCue() {
        let resumed = StepCallOuts.resumed(from: [pastaTimer()], in: pasta, at: 1, now: start.addingTimeInterval(20 * 60))
        #expect(resumed.catchUp == 4)
        #expect(resumed.upcoming.isEmpty)
    }

    @Test func noTimersNoCallOuts() {
        let resumed = StepCallOuts.resumed(from: [], in: pasta, at: 1, now: start)
        #expect(resumed.catchUp == nil)
        #expect(resumed.upcoming.isEmpty)
    }
}
