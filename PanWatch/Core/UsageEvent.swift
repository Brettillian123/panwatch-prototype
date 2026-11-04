import Foundation

/// One thing that happened while the app was in use. Kept on the phone only, one JSON line
/// each (see `UsageLogFile`); nothing is sent anywhere.
struct UsageEvent: Codable, Equatable, Sendable {
    let time: Date
    let kind: Kind

    init(_ kind: Kind, at time: Date) {
        self.kind = kind
        self.time = time
    }

    /// What moved a step.
    enum Source: String, Codable, Sendable {
        case voice, touch, button
        /// The recipe called the step out by itself, when a timer reached its cue.
        case callOut
    }

    /// What became of a timer offer.
    enum Offer: String, Codable, Sendable {
        case made, accepted, dismissed
        /// Gone unanswered: the step changed, the cook left, or the camera went off.
        case expired
    }

    /// Which reader understood a voice command: the keywords, the on-phone model, or neither.
    enum VoicePath: String, Codable, Sendable {
        case keyword, model, none
    }

    enum Kind: Codable, Equatable, Sendable {
        case cookStarted(recipe: String)
        /// `finished`: the cook reached the last step. Otherwise they left for another recipe.
        case cookEnded(recipe: String, finished: Bool)
        /// `step` counts from 1.
        case stepChanged(step: Int, source: Source)
        /// `seconds`: how long the offer waited for its answer; nil when it's made.
        case offer(outcome: Offer, seconds: Double?)
        /// "Start the timer" on a watched step with the camera watching and no offer up,
        /// which likely means the camera missed the ingredient going in. `step` counts from 1.
        case likelyMiss(step: Int)
        /// `milliseconds`: from the end of the utterance to the command. 0 for keywords,
        /// which act at once; the model's own time for the model.
        case voice(heard: String, command: String?, path: VoicePath, milliseconds: Int?)
        case timerStarted(label: String, minutes: Int)
        case timerCancelled(label: String)
        case camera(on: Bool)
        /// A tap on the cooking screen.
        case touch
    }
}

/// The numbers for the judges, worked out from the usage log.
struct UsageSummary: Equatable, Sendable {
    private(set) var cooks = 0
    private(set) var cooksFinished = 0
    private(set) var offersMade = 0
    private(set) var offersAccepted = 0
    private(set) var likelyMisses = 0
    private(set) var touches = 0
    private(set) var voiceCommands = 0
    private(set) var voiceUnderstood = 0
    /// Latencies of the understood commands, kept sorted.
    private var voiceMilliseconds: [Int] = []
    private var days: Set<Date> = []
    private let calendar: Calendar

    init(events: [UsageEvent] = [], calendar: Calendar = .current) {
        self.calendar = calendar
        for event in events { add(event) }
    }

    mutating func add(_ event: UsageEvent) {
        days.insert(calendar.startOfDay(for: event.time))
        switch event.kind {
        case .cookStarted:
            cooks += 1
        case .cookEnded(_, let finished):
            if finished { cooksFinished += 1 }
        case .offer(let outcome, _):
            if outcome == .made { offersMade += 1 }
            if outcome == .accepted { offersAccepted += 1 }
        case .likelyMiss:
            likelyMisses += 1
        case .touch:
            touches += 1
        case .voice(_, let command, _, let milliseconds):
            voiceCommands += 1
            guard command != nil else { break }
            voiceUnderstood += 1
            if let milliseconds {
                let at = voiceMilliseconds.firstIndex { $0 > milliseconds } ?? voiceMilliseconds.endIndex
                voiceMilliseconds.insert(milliseconds, at: at)
            }
        case .stepChanged, .timerStarted, .timerCancelled, .camera:
            break
        }
    }

    /// Share of offers accepted, or nil before the first offer.
    var offersAcceptedShare: Double? {
        offersMade == 0 ? nil : Double(offersAccepted) / Double(offersMade)
    }

    var touchesPerCook: Double? {
        cooks == 0 ? nil : Double(touches) / Double(cooks)
    }

    /// Share of things said that became a command, or nil before anything was heard.
    var voiceUnderstoodShare: Double? {
        voiceCommands == 0 ? nil : Double(voiceUnderstood) / Double(voiceCommands)
    }

    /// Median time from the end of an utterance to its command, or nil before the first.
    var medianVoiceMilliseconds: Double? {
        let values = voiceMilliseconds
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return Double(values[middle - 1] + values[middle]) / 2
        }
        return Double(values[middle])
    }

    /// Calendar days with anything in the log.
    var daysUsed: Int { days.count }
}

/// Turns what the app does into usage events: what moved a step, how long an offer waited,
/// when a cook ends, and what became of each thing heard. Every call takes the time and
/// returns the events to log, in order.
struct UsageTracker: Sendable {
    /// The last input the cook used, which is what moves the next step.
    private(set) var source = UsageEvent.Source.touch
    private var offerSince: Date?
    /// The cook under way and not yet finished.
    private(set) var openCook: String?
    private var voice = VoiceUsageTracker()

    /// Picks up the cook still open at the end of `events`, so a cook resumed after a
    /// relaunch ends properly.
    init(resuming events: [UsageEvent] = []) {
        resume(from: events)
    }

    /// As `init(resuming:)`, for a log that finished loading after the app started. A cook
    /// started since launch wins.
    mutating func resume(from events: [UsageEvent]) {
        guard openCook == nil else { return }
        for event in events.reversed() {
            if case .cookStarted(let recipe) = event.kind {
                openCook = recipe
                return
            }
            if case .cookEnded = event.kind { return }
        }
    }

    mutating func input(_ source: UsageEvent.Source) {
        self.source = source
    }

    mutating func cookStarted(_ recipe: String, at now: Date) -> [UsageEvent] {
        var events = expireOffer(at: now)
        if let open = openCook {
            events.append(UsageEvent(.cookEnded(recipe: open, finished: false), at: now))
        }
        openCook = recipe
        events.append(UsageEvent(.cookStarted(recipe: recipe), at: now))
        return events
    }

    /// `index` counts from 0, of `count` steps. Reaching the last step finishes the cook.
    mutating func stepChanged(to index: Int, of count: Int, at now: Date) -> [UsageEvent] {
        var events = expireOffer(at: now)
        events.append(UsageEvent(.stepChanged(step: index + 1, source: source), at: now))
        if index == count - 1, let open = openCook {
            events.append(UsageEvent(.cookEnded(recipe: open, finished: true), at: now))
            openCook = nil
        }
        return events
    }

    mutating func offerMade(at now: Date) -> [UsageEvent] {
        var events = expireOffer(at: now)
        offerSince = now
        events.append(UsageEvent(.offer(outcome: .made, seconds: nil), at: now))
        return events
    }

    mutating func offerAnswered(accepted: Bool, at now: Date) -> [UsageEvent] {
        guard let since = offerSince else { return [] }
        offerSince = nil
        let seconds = now.timeIntervalSince(since)
        return [UsageEvent(.offer(outcome: accepted ? .accepted : .dismissed, seconds: seconds), at: now)]
    }

    /// The offer went away unanswered, if one was up.
    mutating func expireOffer(at now: Date) -> [UsageEvent] {
        guard let since = offerSince else { return [] }
        offerSince = nil
        return [UsageEvent(.offer(outcome: .expired, seconds: now.timeIntervalSince(since)), at: now)]
    }

    mutating func camera(on: Bool, at now: Date) -> [UsageEvent] {
        (on ? [] : expireOffer(at: now)) + [UsageEvent(.camera(on: on), at: now)]
    }

    // MARK: Voice

    /// The listener's report changed. True when something heard may need settling once the
    /// listener's current work is done (call `settleVoice`).
    mutating func reported(heard: String?, outcome: String?, model: String?) -> Bool {
        voice.reported(heard: heard, outcome: outcome, model: model)
    }

    /// A voice command arrived.
    mutating func command(_ name: String, heard: String, at now: Date) -> [UsageEvent] {
        source = .voice
        return [UsageEvent(voice.command(name, heard: heard), at: now)]
    }

    /// What was heard and never became a command.
    mutating func settleVoice(at now: Date) -> [UsageEvent] {
        voice.settle().map { UsageEvent($0, at: now) }
    }
}

/// Works out the path and time of each voice command from what the listener reports, and
/// which things heard nothing understood. The listener reports, in one go: what it heard,
/// then "no command" for a keyword miss, then "asking the model" if the model is asked.
/// The model's answer comes later as a line like `"text": intent, 120 ms`, just before
/// its command, if any. Long chatter ("ignored: 9 words") isn't counted.
struct VoiceUsageTracker: Sendable {
    private var lastHeard: String?
    private var lastOutcome: String?
    private var lastModel: String?
    /// A keyword miss the model wasn't asked about.
    private var miss: String?
    /// The model's latest answer, until its command arrives or it settles as none.
    private var answer: (heard: String, milliseconds: Int?)?

    static let keywordMiss = "no command"
    static let askingModel = "asking the model"

    mutating func reported(heard: String?, outcome: String?, model: String?) -> Bool {
        var pending = false
        if model != lastModel {
            lastModel = model
            if let model, let reading = Self.modelAnswer(in: model) {
                answer = reading
                pending = true
            }
        }
        if heard != lastHeard || outcome != lastOutcome {
            lastHeard = heard
            lastOutcome = outcome
            // What's heard is reported before its outcome, so a miss is only a miss if the
            // outcome that follows is still "no command".
            if let heard, outcome == Self.keywordMiss {
                miss = heard
                pending = true
            } else if miss == heard {
                miss = nil
            }
        }
        return pending
    }

    mutating func command(_ name: String, heard: String) -> UsageEvent.Kind {
        if miss == heard { miss = nil }
        if let answer, answer.heard == heard {
            self.answer = nil
            return .voice(heard: heard, command: name, path: .model, milliseconds: answer.milliseconds)
        }
        return .voice(heard: heard, command: name, path: .keyword, milliseconds: 0)
    }

    mutating func settle() -> [UsageEvent.Kind] {
        var kinds: [UsageEvent.Kind] = []
        if let miss {
            kinds.append(.voice(heard: miss, command: nil, path: .none, milliseconds: nil))
        }
        if let answer {
            kinds.append(.voice(heard: answer.heard, command: nil, path: .none, milliseconds: answer.milliseconds))
        }
        miss = nil
        answer = nil
        return kinds
    }

    /// The words and milliseconds in a model line, `"text": intent, 120 ms (problem)`.
    static func modelAnswer(in line: String) -> (heard: String, milliseconds: Int?)? {
        guard line.hasPrefix("\"") else { return nil }
        let afterQuote = line.index(after: line.startIndex)
        guard let close = line.range(of: "\": ", range: afterQuote..<line.endIndex) else { return nil }
        let heard = String(line[afterQuote..<close.lowerBound])
        let rest = line[close.upperBound...]
        var milliseconds: Int?
        if let comma = rest.range(of: ", ") {
            let tail = rest[comma.upperBound...]
            let digits = tail.prefix { $0.isASCII && $0.isNumber }
            if !digits.isEmpty, tail.dropFirst(digits.count).hasPrefix(" ms") {
                milliseconds = Int(digits)
            }
        }
        return (heard, milliseconds)
    }
}
