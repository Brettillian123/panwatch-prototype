import Foundation
import Testing
@testable import PanWatchCore

@Suite("Cook stats and saved timers")
struct CookStatsTests {
    @Test func startsAtZero() {
        let stats = CookStats()
        #expect(stats == CookStats())
        #expect(stats.screenTouches == 0)
        #expect(stats.acceptanceRate == nil)
    }

    @Test func eachCounterCountsOnlyItself() {
        var stats = CookStats()
        stats.noteTouch()
        stats.noteVoice()
        stats.noteVoice()
        stats.noteButton()
        #expect(stats.screenTouches == 1)
        #expect(stats.voiceCommands == 2)
        #expect(stats.buttonPresses == 1)
        #expect(stats.offersMade == 0)
    }

    @Test func acceptanceRate() {
        var stats = CookStats()
        stats.noteOffer()
        stats.noteAccepted()
        stats.noteOffer()
        stats.noteDismissed()
        #expect(stats.acceptanceRate == 0.5)
        stats.noteOffer()
        stats.noteAccepted()
        #expect(abs((stats.acceptanceRate ?? 0) - 2.0 / 3.0) < 1e-9)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func savedTimersRoundTrip() {
        let timers = [
            SavedTimer(id: UUID(), label: "Pasta", start: now, end: now.addingTimeInterval(540)),
            SavedTimer(id: UUID(), label: "Garlic", start: now, end: now.addingTimeInterval(60)),
        ]
        #expect(SavedTimers.decode(SavedTimers.encode(timers)) == timers)
    }

    @Test func damagedDataRestoresNothing() {
        #expect(SavedTimers.decode(Data("not json".utf8)).isEmpty)
        #expect(SavedTimers.decode(Data()).isEmpty)
    }

    @Test func finishedTimersAreDropped() {
        let timers = [
            SavedTimer(id: UUID(), label: "Done", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(-1)),
            SavedTimer(id: UUID(), label: "Ending now", start: now.addingTimeInterval(-60), end: now),
            SavedTimer(id: UUID(), label: "Pasta", start: now, end: now.addingTimeInterval(300)),
            SavedTimer(id: UUID(), label: "Rice", start: now, end: now.addingTimeInterval(900)),
        ]
        #expect(SavedTimers.stillRunning(timers, at: now).map(\.label) == ["Pasta", "Rice"])
    }
}
