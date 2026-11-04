import Foundation

/// Runs a practice recording through the same hand rules, hand filter and detector the
/// phone uses, with any tuning, and scores the offers against the cook's markers.
enum PracticeReplay {
    /// An offer counts for a marker within this many seconds of it. The cook says "that
    /// was it" just after the add, and recognizing it takes a moment, so offers land a
    /// few seconds either side.
    static let tolerance = 5.0

    /// Times the replay offers a timer with `settings` as the base tuning. Practice repeats
    /// one step's add many times, so every frame on a watched step is judged, whatever the
    /// phone was doing about its own offers.
    static func offers(in recording: PracticeRecording, settings: DetectorSettings) -> [Double] {
        var watcher = PanWatcher(settings: settings)
        var offers: [Double] = []
        for frame in recording.frames {
            watcher.settings = settings.applying(frame.watch?.watch)
            let aspect = frame.frameHeight > 0 ? Double(frame.frameWidth) / Double(frame.frameHeight) : 1
            let result = watcher.process(
                time: frame.time, hands: frame.hands, aspect: aspect,
                region: frame.region, patch: frame.patch, armed: frame.watch != nil
            )
            if result.decision?.outcome == .addition { offers.append(frame.time) }
        }
        return offers
    }

    static func score(_ recording: PracticeRecording, settings: DetectorSettings) -> DetectionScore {
        DetectionScore.score(labeled: recording.markers, detected: offers(in: recording, settings: settings), tolerance: tolerance)
    }

    /// How the phone itself did while recording.
    static func liveScore(_ recording: PracticeRecording) -> DetectionScore {
        let offers = recording.verdicts.filter { $0.outcome == .addition }.map(\.time)
        return DetectionScore.score(labeled: recording.markers, detected: offers, tolerance: tolerance)
    }

    /// Changes one setting by its name in `DetectorSettings`, like "handConfidence" to "0.4"
    /// or "lightingVeto" to "false". Nil when there's no such setting or the value doesn't fit.
    static func setting(_ name: String, to value: String, in settings: DetectorSettings) -> DetectorSettings? {
        guard let data = try? JSONEncoder().encode(settings),
              var fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              fields[name] != nil else { return nil }
        if let flag = Bool(value) {
            fields[name] = flag
        } else if let whole = Int(value) {
            fields[name] = whole
        } else if let number = Double(value) {
            fields[name] = number
        } else {
            return nil
        }
        guard let changed = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return try? JSONDecoder().decode(DetectorSettings.self, from: changed)
    }
}
