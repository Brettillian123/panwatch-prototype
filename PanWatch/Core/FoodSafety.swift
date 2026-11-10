import Foundation

/// USDA minimum safe internal temperatures, fixed here and never generated: a question
/// about how hot food must get to be safe is answered from this table, not the model.
/// Source: USDA FSIS safe minimum internal temperature chart (research 16, section 3).
enum FoodSafety {
    struct Rule: Equatable, Sendable {
        /// What the cook might call it: "chicken", "ground beef".
        let words: [String]
        let fahrenheit: Int
        /// Minutes to rest after cooking, if the chart asks for one.
        let restMinutes: Int?
        /// The food, as said in the answer.
        let food: String
    }

    /// Checked in order: ground meat before whole cuts, so "ground beef" is 160, not 145.
    static let rules: [Rule] = [
        Rule(words: ["ground", "burger", "burgers", "hamburger", "meatball", "meatballs", "meatloaf", "sausage"],
             fahrenheit: 160, restMinutes: nil, food: "Ground meat"),
        Rule(words: ["chicken", "turkey", "poultry", "duck", "goose", "hen", "wings", "thigh", "thighs", "breast", "breasts"],
             fahrenheit: 165, restMinutes: nil, food: "Poultry"),
        Rule(words: ["leftover", "leftovers", "reheat", "reheated", "reheating", "casserole"],
             fahrenheit: 165, restMinutes: nil, food: "Leftovers"),
        Rule(words: ["fish", "salmon", "tuna", "cod", "tilapia", "halibut", "trout", "shellfish", "shrimp"],
             fahrenheit: 145, restMinutes: nil, food: "Fish"),
        Rule(words: ["beef", "steak", "steaks", "pork", "chop", "chops", "lamb", "veal", "roast", "ham", "tenderloin"],
             fahrenheit: 145, restMinutes: 3, food: "Whole cuts of beef, pork and lamb"),
    ]

    /// Every temperature in the table, so a reply quoting one of them passes the rails.
    static var temperatures: Set<Int> { Set(rules.map(\.fahrenheit)) }
    /// Every rest time in the table.
    static var restMinutes: Set<Int> { Set(rules.compactMap(\.restMinutes)) }

    /// The line when the cook asks whether food is done: the app never says it is.
    static let cannotTell = "I can't tell if it's done. Check the thickest part with a thermometer."

    private static let temperatureWords: Set<String> = [
        "temperature", "temp", "degrees", "degree", "hot", "safe", "safely", "raw", "undercooked", "thermometer",
    ]
    private static let donenessWords: Set<String> = ["done", "ready", "cooked", "finished"]
    private static let askingWords: Set<String> = [
        "is", "are", "it's", "its", "does", "do", "how", "what", "what's", "whats", "when", "should", "can", "will",
    ]

    /// The table's answer to `text`, or nil when it isn't a doneness or safety question.
    /// "What temperature for chicken" gets the chicken line; "is it done" gets
    /// `cannotTell`; "how hot should the oil be" names no food in the table, so it's nil
    /// and goes on to the model, whose reply the rails still check.
    static func answer(to text: String) -> String? {
        let words = Self.words(in: text)
        let rule = rules.first { rule in rule.words.contains(where: words.contains) }
        // A temperature asked for a food in the table, however it's put: "give me a
        // temperature for steak" is answered from the table too.
        if words.contains(where: temperatureWords.contains), let rule {
            return line(for: rule)
        }
        if words.contains(where: askingWords.contains), words.contains(where: donenessWords.contains) {
            if let rule { return "\(cannotTell) \(line(for: rule))" }
            // "Is it done", "is the pasta ready": no temperature to give, only what to check.
            if words.count <= 6 { return cannotTell }
        }
        return nil
    }

    /// "Poultry: 165 degrees Fahrenheit at the thickest part. Check with a thermometer."
    static func line(for rule: Rule) -> String {
        var text = "\(rule.food): \(rule.fahrenheit) degrees Fahrenheit at the thickest part"
        if let rest = rule.restMinutes { text += ", then rest \(rest) minutes" }
        return text + ". Check with a thermometer."
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
}
