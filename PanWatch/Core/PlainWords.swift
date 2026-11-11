import Foundation

/// Brett, Nov 10: technical jargon "will appear as clutter and confuse them". Words from the
/// inside of the app that no cook may see or hear: in the help list, a fixed spoken line,
/// or a recipe.
enum PlainWords {
    static let banned: Set<String> = [
        "mb", "gb", "model", "engine", "sample", "calibrate", "calibrating", "calibration", "exposure",
        "flicker", "frame", "frames", "detection", "debug", "session", "on-device", "ms", "kokoro",
        "pocket", "alarmkit", "foundation", "n/a", "null", "unavailable", "ai",
    ]

    /// The banned words in `text`, in the order they appear.
    static func bannedWords(in text: String) -> [String] {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "/" })
            .map(String.init)
        return words.filter { banned.contains($0) }
    }
}
