import Foundation
import Testing
@testable import PanWatchCore

@Suite("Usage log")
struct UsageLogTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    // MARK: Summary

    @Test func emptySummaryHasNoRates() {
        let summary = UsageSummary(events: [], calendar: utc)
        #expect(summary.cooks == 0)
        #expect(summary.offersAcceptedShare == nil)
        #expect(summary.touchesPerCook == nil)
        #expect(summary.voiceUnderstoodShare == nil)
        #expect(summary.medianVoiceMilliseconds == nil)
        #expect(summary.daysUsed == 0)
    }

    @Test func summaryCountsEachNumber() {
        let day = 86_400.0
        let kinds: [(Double, UsageEvent.Kind)] = [
            (0, .cookStarted(recipe: "Pasta")),
            (1, .touch),
            (2, .offer(outcome: .made, seconds: nil)),
            (5, .offer(outcome: .accepted, seconds: 3)),
            (6, .voice(heard: "next", command: "next", path: .keyword, milliseconds: 0)),
            (7, .voice(heard: "um", command: nil, path: .none, milliseconds: nil)),
            (8, .likelyMiss(step: 3)),
            (9, .cookEnded(recipe: "Pasta", finished: true)),
            (day, .cookStarted(recipe: "Rice")),
            (day + 1, .touch),
            (day + 2, .touch),
            (day + 3, .touch),
            (day + 4, .offer(outcome: .made, seconds: nil)),
            (day + 5, .offer(outcome: .dismissed, seconds: 1)),
            (day + 6, .offer(outcome: .made, seconds: nil)),
            (day + 7, .offer(outcome: .accepted, seconds: 1)),
            (day + 8, .voice(heard: "keep it going", command: "next", path: .model, milliseconds: 300)),
            (day + 9, .voice(heard: "stop", command: "cancelTimer", path: .keyword, milliseconds: 0)),
            (day + 10, .stepChanged(step: 2, source: .voice)),
            (day + 11, .timerStarted(label: "Rice", minutes: 15)),
            (day + 12, .camera(on: false)),
        ]
        let summary = UsageSummary(events: kinds.map { UsageEvent($0.1, at: at($0.0)) }, calendar: utc)
        #expect(summary.cooks == 2)
        #expect(summary.cooksFinished == 1)
        #expect(summary.offersMade == 3)
        #expect(abs((summary.offersAcceptedShare ?? 0) - 2.0 / 3.0) < 1e-9)
        #expect(summary.likelyMisses == 1)
        #expect(summary.touchesPerCook == 2)
        #expect(summary.voiceCommands == 4)
        #expect(summary.voiceUnderstoodShare == 0.75)
        #expect(summary.medianVoiceMilliseconds == 0)
        #expect(summary.daysUsed == 2)
    }

    @Test func medianOfAnEvenCountIsTheMiddlePair() {
        let events = [500, 100, 300, 0].map {
            UsageEvent(.voice(heard: "x", command: "next", path: .model, milliseconds: $0), at: start)
        }
        #expect(UsageSummary(events: events, calendar: utc).medianVoiceMilliseconds == 200)
        let odd = Array(events.prefix(3))
        #expect(UsageSummary(events: odd, calendar: utc).medianVoiceMilliseconds == 300)
    }

    // MARK: Tracker

    @Test func stepsTakeTheirSourceAndTheLastStepFinishesTheCook() {
        var tracker = UsageTracker()
        var events = tracker.cookStarted("Pasta", at: at(0))
        tracker.input(.touch)
        events += tracker.stepChanged(to: 1, of: 4, at: at(1))
        tracker.input(.button)
        events += tracker.stepChanged(to: 2, of: 4, at: at(2))
        tracker.input(.callOut)
        events += tracker.stepChanged(to: 3, of: 4, at: at(3))
        tracker.input(.voice)
        events += tracker.stepChanged(to: 2, of: 4, at: at(4))
        #expect(events.map(\.kind) == [
            .cookStarted(recipe: "Pasta"),
            .stepChanged(step: 2, source: .touch),
            .stepChanged(step: 3, source: .button),
            .stepChanged(step: 4, source: .callOut),
            .cookEnded(recipe: "Pasta", finished: true),
            .stepChanged(step: 3, source: .voice),
        ])
        #expect(tracker.openCook == nil)
    }

    @Test func aNewCookEndsTheOpenOneAsLeft() {
        var tracker = UsageTracker()
        _ = tracker.cookStarted("Pasta", at: at(0))
        let events = tracker.cookStarted("Rice", at: at(60))
        #expect(events.map(\.kind) == [.cookEnded(recipe: "Pasta", finished: false), .cookStarted(recipe: "Rice")])
    }

    @Test func offersAreTimedAndExpireWhenTheyGoUnanswered() {
        var tracker = UsageTracker()
        var events = tracker.offerMade(at: at(0))
        events += tracker.offerAnswered(accepted: true, at: at(4))
        events += tracker.offerAnswered(accepted: false, at: at(5))
        events += tracker.offerMade(at: at(10))
        events += tracker.offerAnswered(accepted: false, at: at(12))
        events += tracker.offerMade(at: at(20))
        events += tracker.stepChanged(to: 1, of: 5, at: at(27))
        events += tracker.offerMade(at: at(30))
        events += tracker.camera(on: false, at: at(31))
        events += tracker.offerMade(at: at(40))
        events += tracker.expireOffer(at: at(42))
        events += tracker.expireOffer(at: at(43))
        #expect(events.map(\.kind) == [
            .offer(outcome: .made, seconds: nil),
            .offer(outcome: .accepted, seconds: 4),
            .offer(outcome: .made, seconds: nil),
            .offer(outcome: .dismissed, seconds: 2),
            .offer(outcome: .made, seconds: nil),
            .offer(outcome: .expired, seconds: 7),
            .stepChanged(step: 2, source: .touch),
            .offer(outcome: .made, seconds: nil),
            .offer(outcome: .expired, seconds: 1),
            .camera(on: false),
            .offer(outcome: .made, seconds: nil),
            .offer(outcome: .expired, seconds: 2),
        ])
    }

    @Test func aResumedCookIsPickedUpFromTheLog() {
        let finished = [
            UsageEvent(.cookStarted(recipe: "Pasta"), at: at(0)),
            UsageEvent(.cookEnded(recipe: "Pasta", finished: true), at: at(1)),
        ]
        #expect(UsageTracker(resuming: finished).openCook == nil)
        let open = finished + [UsageEvent(.cookStarted(recipe: "Rice"), at: at(2)), UsageEvent(.touch, at: at(3))]
        var tracker = UsageTracker(resuming: open)
        #expect(tracker.openCook == "Rice")
        // A cook started before the log finished loading wins.
        var late = UsageTracker()
        _ = late.cookStarted("Eggs", at: at(4))
        late.resume(from: open)
        #expect(late.openCook == "Eggs")
        #expect(tracker.stepChanged(to: 2, of: 3, at: at(5)).last?.kind == .cookEnded(recipe: "Rice", finished: true))
    }

    // MARK: Voice

    /// The listener's report, telling the tracker about each change the way the listener
    /// does: only when something in it changed.
    private struct Report {
        var heard: String?
        var outcome: String?
        var model: String?
        /// Something may need settling.
        var pending = false

        mutating func set(heard: String? = nil, outcome: String? = nil, model: String? = nil, _ tracker: inout UsageTracker) {
            var next = self
            if let heard { next.heard = heard }
            if let outcome { next.outcome = outcome }
            if let model { next.model = model }
            guard next.heard != self.heard || next.outcome != self.outcome || next.model != self.model else { return }
            self = next
            pending = tracker.reported(heard: next.heard, outcome: next.outcome, model: next.model) || pending
        }

        /// One utterance: what was heard, then each outcome in turn.
        mutating func say(_ text: String, _ outcomes: [String], _ tracker: inout UsageTracker) {
            pending = false
            set(heard: text, &tracker)
            for outcome in outcomes { set(outcome: outcome, &tracker) }
        }
    }

    @Test func keywordsActAtOnceAndMissesSettleAsNone() {
        var tracker = UsageTracker()
        var report = Report()
        report.say("next", ["next"], &tracker)
        var events = tracker.command("next", heard: "next", at: at(0))
        #expect(tracker.settleVoice(at: at(0)).isEmpty)
        report.say("um okay", ["no command"], &tracker)
        #expect(report.pending)
        events += tracker.settleVoice(at: at(1))
        // A second miss leaves the outcome as it was; the new words still count.
        report.say("uh huh", ["no command"], &tracker)
        events += tracker.settleVoice(at: at(2))
        // Long chatter isn't counted.
        report.say("so then she said the thing about the car", ["ignored: 9 words"], &tracker)
        events += tracker.settleVoice(at: at(3))
        // A keyword after a miss, then the same keyword again, which changes nothing in the report.
        report.say("next", ["no command", "next"], &tracker)
        events += tracker.command("next", heard: "next", at: at(4))
        events += tracker.settleVoice(at: at(4))
        report.say("next", ["next"], &tracker)
        events += tracker.command("next", heard: "next", at: at(5))
        events += tracker.settleVoice(at: at(5))
        #expect(events.map(\.kind) == [
            .voice(heard: "next", command: "next", path: .keyword, milliseconds: 0),
            .voice(heard: "um okay", command: nil, path: .none, milliseconds: nil),
            .voice(heard: "uh huh", command: nil, path: .none, milliseconds: nil),
            .voice(heard: "next", command: "next", path: .keyword, milliseconds: 0),
            .voice(heard: "next", command: "next", path: .keyword, milliseconds: 0),
        ])
        #expect(tracker.source == .voice)
    }

    @Test func theModelsAnswersCarryItsTime() {
        var tracker = UsageTracker()
        var report = Report()
        report.say("keep it going", ["no command", "asking the model"], &tracker)
        // Asked: nothing settles until the model answers.
        #expect(tracker.settleVoice(at: at(0)).isEmpty)
        report.set(model: "\"keep it going\": next, 412 ms", &tracker)
        report.set(outcome: "model: next", &tracker)
        #expect(report.pending)
        var events = tracker.command("next", heard: "keep it going", at: at(1))
        events += tracker.settleVoice(at: at(1))
        report.say("what a nice day", ["no command", "asking the model"], &tracker)
        report.set(model: "\"what a nice day\": none, 380 ms", &tracker)
        report.set(outcome: "model: none", &tracker)
        events += tracker.settleVoice(at: at(2))
        #expect(events.map(\.kind) == [
            .voice(heard: "keep it going", command: "next", path: .model, milliseconds: 412),
            .voice(heard: "what a nice day", command: nil, path: .none, milliseconds: 380),
        ])
    }

    @Test func modelLinesAreRead() {
        let full = VoiceUsageTracker.modelAnswer(in: "\"go on\": next, 95 ms (dropped: things moved on)")
        #expect(full?.heard == "go on")
        #expect(full?.milliseconds == 95)
        let broken = VoiceUsageTracker.modelAnswer(in: "\"hm\": none, ? ms")
        #expect(broken?.heard == "hm")
        #expect(broken?.milliseconds == nil)
        #expect(VoiceUsageTracker.modelAnswer(in: "Off: keywords only") == nil)
    }

    // MARK: File

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-\(UUID().uuidString)")
            .appendingPathComponent("usage-log.jsonl")
    }

    @Test func eventsRoundTripAsJSONLines() throws {
        let file = UsageLogFile(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        #expect(file.load().isEmpty)
        let first = [
            UsageEvent(.cookStarted(recipe: "Pasta"), at: at(0)),
            UsageEvent(.voice(heard: "start the timer", command: "startTimer", path: .keyword, milliseconds: 0), at: at(1)),
        ]
        let second = [
            UsageEvent(.offer(outcome: .accepted, seconds: 2.5), at: at(2)),
            UsageEvent(.touch, at: at(3)),
        ]
        try file.append(first)
        try file.append(second)
        #expect(file.load() == first + second)
        let text = try String(contentsOf: file.url, encoding: .utf8)
        #expect(text.split(separator: "\n").count == 4)
        #expect(text.hasSuffix("\n"))
    }

    @Test func aBadLineIsSkipped() throws {
        let file = UsageLogFile(url: temporaryFile())
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try file.append([UsageEvent(.touch, at: at(0))])
        let handle = try FileHandle(forWritingTo: file.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"half a line".utf8))
        try handle.close()
        try file.append([UsageEvent(.camera(on: true), at: at(1))])
        #expect(file.load().map(\.kind) == [.touch])
    }

    @Test func pastTheLimitTheOldestLinesGo() throws {
        let file = UsageLogFile(url: temporaryFile(), limit: 2_000)
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        for step in 1...100 {
            try file.append([UsageEvent(.stepChanged(step: step, source: .touch), at: at(Double(step)))])
        }
        let size = try Data(contentsOf: file.url).count
        #expect(size <= 2_000)
        let kept = file.load()
        #expect(!kept.isEmpty)
        #expect(kept.last?.kind == .stepChanged(step: 100, source: .touch))
        // Whole lines only, newest kept in order.
        let steps = kept.compactMap { event -> Int? in
            if case .stepChanged(let step, _) = event.kind { return step }
            return nil
        }
        #expect(steps.count == kept.count)
        #expect(steps == Array((101 - steps.count)...100))
    }
}
