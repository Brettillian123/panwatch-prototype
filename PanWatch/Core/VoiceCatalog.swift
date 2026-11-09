import Foundation

/// Where a natural voice is from, as the cook hears it.
enum VoiceAccent: String, CaseIterable, Codable, Sendable {
    case american, british

    /// The menu heading and the word said back.
    var title: String {
        switch self {
        case .american: "American"
        case .british: "British"
        }
    }

    /// "Use the British voice", "use an English one": the words that mean this accent.
    static func heard(_ word: String) -> VoiceAccent? {
        switch word {
        case "american", "us", "usa", "america": .american
        case "british", "english", "uk", "england", "london": .british
        default: nil
        }
    }
}

enum VoiceGender: String, CaseIterable, Codable, Sendable {
    case female, male

    static func heard(_ word: String) -> VoiceGender? {
        switch word {
        case "female", "woman", "woman's", "lady", "girl", "women": .female
        case "male", "man", "man's", "guy", "men", "boy": .male
        default: nil
        }
    }
}

/// One of the Kokoro voices the app offers, under a plain first name. The model's own
/// voice names (af_heart and the rest) never reach the screen.
struct NaturalVoice: Identifiable, Equatable, Codable, Sendable {
    /// The Kokoro voice pack, such as "af_heart".
    let pack: String
    let name: String
    let accent: VoiceAccent
    let gender: VoiceGender
    /// One line in plain words, shown under the name.
    let detail: String

    /// The id the voice menu and `Speaker` use; never an Apple voice identifier.
    var id: String { VoiceCatalog.idPrefix + pack }
}

/// A voice the cook mixed from two others: `first` at `balance`, `second` at the rest.
struct VoiceBlend: Equatable, Codable, Sendable {
    var name: String
    var first: String
    var second: String
    /// How much of `first`, from 0 to 1.
    var balance: Double
    /// The Kokoro pack the mix is saved as, such as "af_mix3".
    var pack: String

    var voice: NaturalVoice {
        let a = VoiceCatalog.voice(pack: first)
        let b = VoiceCatalog.voice(pack: second)
        let lead = balance >= 0.5 ? a : b
        let detail = "Mix of \(a?.name ?? first) and \(b?.name ?? second)"
        return NaturalVoice(
            pack: pack, name: name, accent: lead?.accent ?? .american, gender: lead?.gender ?? .female, detail: detail)
    }
}

/// How fast every voice talks, Apple's and Kokoro's alike.
enum VoiceSpeed: String, CaseIterable, Codable, Sendable {
    case slower, normal, faster

    var title: String {
        switch self {
        case .slower: "Slower"
        case .normal: "Normal"
        case .faster: "Faster"
        }
    }

    /// Kokoro's speed, and a multiplier on Apple's default speaking rate.
    var factor: Float {
        switch self {
        case .slower: 0.85
        case .normal: 1.0
        case .faster: 1.15
        }
    }

    /// One step slower or faster, staying at the ends.
    func step(faster: Bool) -> VoiceSpeed {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return all[max(0, min(all.count - 1, index + (faster ? 1 : -1)))]
    }
}

/// The Kokoro voices offered in the voice menu, and the pure parts of speaking in them.
enum VoiceCatalog {
    static let idPrefix = "kokoro:"

    /// Kokoro's best-graded American and British voices (hexgrad/Kokoro-82M VOICES.md),
    /// best first within each accent and gender. The default is the first.
    static let voices: [NaturalVoice] = [
        NaturalVoice(pack: "af_heart", name: "Hannah", accent: .american, gender: .female, detail: "Warm and clear"),
        NaturalVoice(pack: "af_bella", name: "Bella", accent: .american, gender: .female, detail: "Bright and friendly"),
        NaturalVoice(pack: "af_nicole", name: "Nicole", accent: .american, gender: .female, detail: "Soft and calm, close to a whisper"),
        NaturalVoice(pack: "af_sarah", name: "Sarah", accent: .american, gender: .female, detail: "Even and steady"),
        NaturalVoice(pack: "af_kore", name: "Kora", accent: .american, gender: .female, detail: "Low and relaxed"),
        NaturalVoice(pack: "am_michael", name: "Michael", accent: .american, gender: .male, detail: "Deep and easygoing"),
        NaturalVoice(pack: "am_fenrir", name: "Finn", accent: .american, gender: .male, detail: "Firm and direct"),
        NaturalVoice(pack: "bf_emma", name: "Emma", accent: .british, gender: .female, detail: "Clear and polite"),
        NaturalVoice(pack: "bm_george", name: "George", accent: .british, gender: .male, detail: "Older, low and measured"),
        NaturalVoice(pack: "bm_fable", name: "Felix", accent: .british, gender: .male, detail: "Lively storyteller"),
    ]

    /// Kokoro's own default voice is the even mix of Bella and Sarah (model card).
    static let bellaAndSarah = VoiceBlend(
        name: "Bella and Sarah", first: "af_bella", second: "af_sarah", balance: 0.5, pack: "af_mixbs")

    static var defaultVoice: NaturalVoice { voices[0] }

    static func voice(pack: String) -> NaturalVoice? {
        voices.first { $0.pack == pack }
    }

    static func isNatural(_ id: String?) -> Bool {
        id?.hasPrefix(idPrefix) ?? false
    }

    /// The Kokoro pack in a voice-menu id, or nil for an Apple voice.
    static func pack(fromID id: String?) -> String? {
        guard let id, id.hasPrefix(idPrefix) else { return nil }
        let pack = String(id.dropFirst(idPrefix.count))
        return isValidPack(pack) ? pack : nil
    }

    /// Kokoro's English packs: a/b, f/m, underscore, then lowercase letters and digits.
    static func isValidPack(_ pack: String) -> Bool {
        let prefixes = ["af_", "am_", "bf_", "bm_"]
        guard prefixes.contains(where: pack.hasPrefix), pack.count > 3, pack.count <= 32 else { return false }
        return pack.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 95 }
    }

    /// The pack name for a new mix, led by whichever voice has more of the balance, so
    /// Kokoro reads it with that voice's accent. `number` keeps every saved mix distinct.
    static func blendPack(first: String, second: String, balance: Double, number: Int) -> String? {
        let lead = balance >= 0.5 ? first : second
        guard isValidPack(lead), number >= 0 else { return nil }
        return String(lead.prefix(3)) + "mix\(number)"
    }

    /// The voices in menu order: American then British, female then male, as listed,
    /// then the cook's own mixes.
    static func menuOrder(blends: [VoiceBlend]) -> [NaturalVoice] {
        let fixed = VoiceAccent.allCases.flatMap { accent in voices.filter { $0.accent == accent } }
        return fixed + blends.map(\.voice)
    }

    /// The next voice after `current` with this accent and gender (either may be nil),
    /// wrapping round; nil when none matches.
    static func next(
        after current: String?, accent: VoiceAccent?, gender: VoiceGender?, in list: [NaturalVoice]
    ) -> NaturalVoice? {
        let matching = list.filter { (accent == nil || $0.accent == accent) && (gender == nil || $0.gender == gender) }
        guard !matching.isEmpty else { return nil }
        guard let at = matching.firstIndex(where: { $0.id == current }) else { return matching[0] }
        return matching[(at + 1) % matching.count]
    }

    /// A weighted mix of two voice packs, element by element; nil when the sizes differ.
    static func mix(_ a: [Float], _ b: [Float], balance: Double) -> [Float]? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        let w = Float(max(0, min(1, balance)))
        return zip(a, b).map { w * $0 + (1 - w) * $1 }
    }

    /// `text` split into sentences, so the first can play while the rest are made. Short
    /// pieces join the one before, and a sentence over `limit` characters is cut at a
    /// comma or space, since Kokoro takes at most 510 phonemes at once.
    static func sentences(in text: String, limit: Int = 220) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?;\n".contains(character) {
                pieces.append(current)
                current = ""
            }
        }
        pieces.append(current)
        var out: [String] = []
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let last = out.last, trimmed.count < 12 || !trimmed.contains(where: \.isLetter) {
                out[out.count - 1] = last + " " + trimmed
            } else {
                out.append(trimmed)
            }
        }
        return out.flatMap { cut($0, limit: limit) }
    }

    private static func cut(_ sentence: String, limit: Int) -> [String] {
        var rest = Substring(sentence)
        var out: [String] = []
        while rest.count > limit {
            let window = rest.prefix(limit)
            let at = window.lastIndex(of: ",") ?? window.lastIndex(of: " ") ?? window.endIndex
            let head = rest[..<(at == window.endIndex ? at : rest.index(after: at))]
            out.append(head.trimmingCharacters(in: .whitespaces))
            rest = rest[head.endIndex...].drop { $0 == " " }
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }
}
