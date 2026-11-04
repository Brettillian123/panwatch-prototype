import Foundation

/// The pure rules behind barge-in: the cook starts talking while the app reads a step,
/// and the app stops at once. Voice processing cancels most of the app's own voice from
/// the microphone, but not all of it, so these guard against the app interrupting itself.
enum SelfEcho {
    /// The words in `heard` that the app wasn't saying: what the cook added. Recognition
    /// hearing a trace of the app's own voice gives words from `spoken` only, which don't
    /// count; one word of the cook's own does.
    static func newWords(in heard: String, spoken: String?) -> [String] {
        let own = Set(words(in: spoken ?? ""))
        return words(in: heard).filter { !own.contains($0) }
    }

    /// `heard` without the words the app was saying at the time, in the order the cook
    /// said them, so the command is judged from the cook's words alone.
    static func strip(_ heard: String, spoken: String?) -> String {
        newWords(in: heard, spoken: spoken).joined(separator: " ")
    }

    static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
}

/// Decides from the microphone level when someone is speaking: loud for `holdSeconds`
/// without a break starts speech; quiet for `releaseSeconds` ends it. The gap between the
/// two thresholds keeps a word's dips and a sizzle's pops from flipping it back and forth.
struct SpeechDetector: Equatable {
    /// RMS level, full scale 1.0, that counts as loud. -34 dBFS: a voice at arm's length
    /// over an echo-cancelled input, above the residue of the app's own voice.
    var threshold = 0.02
    var holdSeconds = 0.25
    var releaseSeconds = 0.5
    private(set) var isSpeech = false
    private var loudSince: Double?
    private var quietSince: Double?

    /// Feeds one level reading taken at `time` (seconds, any zero). True at the moment
    /// speech starts, and only then.
    mutating func feed(level: Double, at time: Double) -> Bool {
        if isSpeech {
            if level < threshold / 2 {
                if quietSince == nil { quietSince = time }
                if time - (quietSince ?? time) >= releaseSeconds {
                    isSpeech = false
                    quietSince = nil
                    loudSince = nil
                }
            } else {
                quietSince = nil
            }
            return false
        }
        guard level >= threshold else {
            loudSince = nil
            return false
        }
        if loudSince == nil { loudSince = time }
        if time - (loudSince ?? time) >= holdSeconds {
            isSpeech = true
            loudSince = nil
            quietSince = nil
            return true
        }
        return false
    }

    mutating func reset() {
        self = SpeechDetector(threshold: threshold, holdSeconds: holdSeconds, releaseSeconds: releaseSeconds)
    }
}
