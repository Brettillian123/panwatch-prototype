import Foundation
import Observation

/// The on-phone usage log: what happened in each cook, appended to a file in Application
/// Support and summed up in the details panel. Nothing is sent anywhere; "Share usage log"
/// hands the file to the share sheet, and the cook decides where it goes.
@MainActor
@Observable
final class UsageLog {
    private(set) var summary = UsageSummary()
    /// The log file, for the share sheet; nil if Application Support can't be found.
    let fileURL: URL?
    private let file: UsageLogFile?
    @ObservationIgnored private var tracker = UsageTracker()

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let file = folder.map { UsageLogFile(url: $0.appendingPathComponent("usage-log.jsonl")) }
        self.file = file
        fileURL = file?.url
        // Read the old log off the main thread; it can be a few megabytes.
        guard let file else {
            isLoaded = true
            return
        }
        Task { [weak self] in
            let old = await Task.detached(priority: .utility) { file.load() }.value
            self?.loaded(old)
        }
    }

    private func loaded(_ old: [UsageEvent]) {
        tracker.resume(from: old)
        var all = UsageSummary(events: old)
        for event in waiting { all.add(event) }
        summary = all
        isLoaded = true
        try? file?.append(waiting)
        waiting = []
    }

    /// Events logged before the old log finished loading, written once it has so they
    /// aren't read back twice.
    @ObservationIgnored private var waiting: [UsageEvent] = []
    @ObservationIgnored private var isLoaded = false

    private func record(_ events: [UsageEvent]) {
        guard !events.isEmpty else { return }
        for event in events { summary.add(event) }
        if isLoaded {
            try? file?.append(events)
        } else {
            waiting += events
        }
    }

    // MARK: Inputs

    /// A tap on the cooking screen.
    func touched() {
        tracker.input(.touch)
        record([UsageEvent(.touch, at: Date())])
    }

    /// A volume button or Camera Control press.
    func button() { tracker.input(.button) }

    /// The recipe is about to call a step out by itself.
    func callOut() { tracker.input(.callOut) }

    func heard(_ command: VoiceCommand, text: String) {
        record(tracker.command("\(command)", heard: text, at: Date()))
    }

    /// The listener's report changed. Things heard that never became a command are settled
    /// once the listener has finished acting on them.
    func listened(_ report: VoiceReport) {
        guard tracker.reported(heard: report.heard, outcome: report.outcome, model: report.model) else { return }
        Task { [weak self] in
            guard let self else { return }
            self.record(self.tracker.settleVoice(at: Date()))
        }
    }

    // MARK: The cook

    func cookStarted(_ recipe: String) { record(tracker.cookStarted(recipe, at: Date())) }

    /// `index` counts from 0.
    func stepChanged(to index: Int, of count: Int) { record(tracker.stepChanged(to: index, of: count, at: Date())) }

    func offerMade() { record(tracker.offerMade(at: Date())) }

    func offerAnswered(accepted: Bool) { record(tracker.offerAnswered(accepted: accepted, at: Date())) }

    /// The offer, if one was up, went away unanswered.
    func offerGone() { record(tracker.expireOffer(at: Date())) }

    /// "Start the timer" with no offer up. Counted only when the camera was watching the pan.
    func likelyMiss(step index: Int, watching: Bool) {
        guard watching else { return }
        record([UsageEvent(.likelyMiss(step: index + 1), at: Date())])
    }

    func timerStarted(_ label: String, minutes: Int) {
        record([UsageEvent(.timerStarted(label: label, minutes: minutes), at: Date())])
    }

    /// A timer taken off the list; cancelled if it hadn't rung yet.
    func timerRemoved(_ timer: CookTimer?) {
        guard let timer, !timer.isDone else { return }
        record([UsageEvent(.timerCancelled(label: timer.label), at: Date())])
    }

    func camera(on: Bool) { record(tracker.camera(on: on, at: Date())) }
}
