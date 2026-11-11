import Foundation

extension Recipe {
    /// Mistakes that would make the recipe misbehave in the kitchen, in plain words.
    /// Empty means the recipe is fine. Every recipe in `Recipe.all` is checked by a test.
    func problems() -> [String] {
        var found: [String] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            found.append("The recipe has no title.")
        }
        if steps.isEmpty {
            found.append("The recipe has no steps.")
        }
        // Timers started by earlier steps, with their length in seconds. A cue can only
        // wait on one of these, because the session schedules cues when a timer starts.
        var earlierTimers: [String: Int] = [:]
        for (index, step) in steps.enumerated() {
            let name = "Step \(step.id)"
            if step.id != index + 1 {
                found.append("\(name): ids must run 1, 2, 3 in order; expected \(index + 1).")
            }
            if step.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append("\(name): the instruction is empty.")
            }
            if let cue = step.cue {
                if cue.secondsLeft < 0 {
                    found.append("\(name): the cue has negative time left.")
                }
                if let length = earlierTimers[cue.timerLabel] {
                    if cue.secondsLeft > length {
                        found.append("\(name): the cue waits for \(cue.secondsLeft) s left on \"\(cue.timerLabel)\", which only runs \(length) s.")
                    }
                } else {
                    found.append("\(name): the cue names timer \"\(cue.timerLabel)\", but no earlier step starts it.")
                }
            }
            if let watch = step.watch {
                if watch.timerMinutes <= 0 {
                    found.append("\(name): the timer must be at least 1 minute.")
                }
                if watch.ingredient.trimmingCharacters(in: .whitespaces).isEmpty
                    || watch.timerLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    found.append("\(name): the watch needs an ingredient and a timer name.")
                }
                if let change = watch.minimumChange, change < 0 || change > 1 {
                    found.append("\(name): the share of the pan that must change has to be between 0 and 1.")
                }
                earlierTimers[watch.timerLabel] = watch.timerMinutes * 60
            }
            // A plain timer starts the same way (on a tap or a "yes"), so a cue may wait on it too.
            if let timer = step.timer { earlierTimers[timer.label] = timer.minutes * 60 }
        }
        return found
    }

    /// Everything `problems()` finds, plus the rules for writing a recipe for the book
    /// (`Recipes/README.md`): sizes, wording, units, timers and the camera.
    func authoringProblems() -> [String] {
        var found = problems()
        found += RecipeRules.titleProblems(title)
        if let serves, !RecipeRules.servesRange.contains(serves) {
            found.append("\"serves\" must be 1 to \(RecipeRules.servesRange.upperBound), or left out; it is \(serves).")
        }
        if !RecipeRules.totalRange.contains(totalMinutes) {
            found.append("\"totalMinutes\" must be 1 to \(RecipeRules.totalRange.upperBound); it is \(totalMinutes).")
        }
        let timed = steps.reduce(0) { $0 + ($1.watch?.timerMinutes ?? 0) + ($1.timer?.minutes ?? 0) }
        if totalMinutes < timed {
            found.append("\"totalMinutes\" is \(totalMinutes), less than its timers add up to (\(timed)).")
        }
        if !RecipeRules.stepRange.contains(steps.count) {
            found.append("A recipe has 3 to \(RecipeRules.stepRange.upperBound) steps; this one has \(steps.count).")
        }
        if !source.isOwn && !source.url.hasPrefix("https://") {
            found.append("A recipe from elsewhere needs the source's \"url\", starting https://.")
        }

        let timerMinutes = Set(steps.compactMap(\.watch?.timerMinutes) + steps.compactMap(\.timer?.minutes))
        for step in steps {
            let name = "Step \(step.id)"
            found += RecipeRules.instructionProblems(step.instruction).map { "\(name): \($0)" }
            for text in [step.instruction, step.spoken].compactMap({ $0 }) {
                found += RecipeRules.wordProblems(text).map { "\(name): \($0)" }
                // Off the heat too: "let it rest 5 minutes" needs its 5-minute timer.
                // A range, "7 to 10 minutes", is covered by a timer on either number.
                for time in RecipeRules.statedTimes(in: text) where timerMinutes.isDisjoint(with: time.covered) {
                    let wait = RecipeRules.isOffTheHeat(text) ? " (waits off the heat need a timer too)" : ""
                    found.append("\(name): it says \(time.minutes) minutes, but no step has a \(time.minutes)-minute timer\(wait).")
                }
            }
            if let spoken = step.spoken {
                found += RecipeRules.numberProblems(shown: step.instruction, spoken: spoken).map { "\(name): \($0)" }
            }
            if let watch = step.watch {
                if !method.cameraCanHelp {
                    found.append("\(name): only pot and pan recipes have a \"watch\"; this one is \(method.rawValue).")
                } else if !RecipeRules.addsSomething(step.instruction) {
                    found.append("\(name): a \"watch\" belongs on a step that adds something to the pot or pan (Add, Stir in, Lower, Lay...).")
                }
                if watch.timerMinutes > RecipeRules.timerRange.upperBound {
                    found.append("\(name): a watch timer runs 1 to \(RecipeRules.timerRange.upperBound) minutes.")
                }
                found += RecipeRules.wordProblems(watch.ingredient + " " + watch.timerLabel).map { "\(name): \($0)" }
            }
            if let timer = step.timer {
                if !RecipeRules.timerRange.contains(timer.minutes) {
                    found.append("\(name): a timer runs 1 to \(RecipeRules.timerRange.upperBound) minutes.")
                }
                if timer.label.trimmingCharacters(in: .whitespaces).isEmpty { found.append("\(name): the timer needs a label.") }
                if step.watch != nil { found.append("\(name): a step has a \"watch\" or a \"timer\", not both.") }
            }
        }

        if items.isEmpty { found.append("The recipe lists no ingredients.") }
        let stepText = steps.map { $0.instruction + " " + ($0.spoken ?? "") }.joined(separator: " ")
        for item in items {
            let label = "Ingredient \"\(item.name)\""
            if item.name.trimmingCharacters(in: .whitespaces).isEmpty { found.append("An ingredient has no name.") }
            if let problem = RecipeRules.amountProblem(item.amount) { found.append("\(label): \(problem)") }
            if !item.name.isEmpty, !RecipeRules.isUsed(item.name, in: stepText) {
                found.append("\(label) is never named in a step.")
            }
            found += RecipeRules.wordProblems(item.name).map { "\(label): \($0)" }
        }
        return found
    }
}

/// The wording rules behind `authoringProblems()`, in one place so the README and the
/// tests can point at them.
enum RecipeRules {
    static let instructionLimit = 90
    static let titleLimit = 40
    /// How many it feeds, when the source says: big batches and party trays included.
    static let servesRange = 1...100
    /// Steps in a recipe: a long cookbook recipe written one action per step fits.
    static let stepRange = 3...20
    /// One timer, watch or plain: up to an eight-hour slow cooker.
    static let timerRange = 1...480
    /// Start to plate: up to a day, for overnight rises and chills.
    static let totalRange = 1...1_440

    /// Words a title keeps lowercase unless they come first: "Chicken with Rice", "Dulce de Leche".
    static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "with",
        "de", "la", "le", "el", "con", "al", "à", "au", "di", "da",
    ]

    /// US kitchen units and counts, singular; a plural "s" or "es" is fine too.
    static let units: Set<String> = [
        "cup", "tablespoon", "teaspoon", "pound", "ounce", "fluid ounce", "quart", "pint", "gallon",
        "clove", "pinch", "dash", "can", "jar", "stick", "slice", "piece", "bunch", "head", "sprig",
        "stalk", "ear", "inch", "bowl", "handful", "package", "bag", "box", "leaf", "loaf",
        "cube", "strip", "wedge", "bottle", "packet", "envelope", "drop", "fillet", "breast", "thigh",
        "rib", "link", "sheet",
    ]
    /// Words that may sit between the number and the unit: "1 large", "2 heaping tablespoons".
    static let sizes: Set<String> = ["large", "medium", "small", "heaping", "level", "scant", "generous", "big"]

    /// The first words of a step that puts something into the pot or pan.
    static let addingStarts = [
        "add", "stir in", "lower", "lay", "drop", "put", "pour", "place", "slide", "crack",
        "tip", "spoon", "scatter", "sprinkle", "toss in", "set", "return",
    ]

    /// Waits off the heat may name their minutes without a timer: resting, cooling, soaking.
    static let offHeatWords = ["rest", "sit", "stand", "cool", "chill", "soak", "marinate", "ice water", "refrigerate"]

    /// Brand names a recipe must not use: say what the thing is instead.
    static let brands: [String] = [
        "kraft", "barilla", "heinz", "tabasco", "pyrex", "crock-pot", "crockpot", "instant pot", "velveeta",
        "kikkoman", "morton", "diamond crystal", "philadelphia", "jell-o", "spam", "ziploc", "saran", "nutella",
        "bisquick", "cheerios", "old bay", "lawry's", "mccormick", "campbell's", "hellmann's", "best foods",
        "land o lakes", "land o'lakes", "kerrygold", "crisco", "teflon", "le creuset", "kitchenaid",
        "cuisinart", "vitamix", "oreo", "goya", "swanson", "knorr", "better than bouillon", "frank's",
        "cholula", "huy fong", "quaker", "uncle ben's", "minute rice", "rice-a-roni", "pam",
    ]

    /// Phrases where the app would be saying the food is done, safe or at a temperature.
    static let claims = [
        #"\b(is|are|it's|they're|it is|they are)\s+(now\s+)?(done|ready|cooked|safe|perfect)\b"#,
        #"\b(has|have)\s+reached\b"#,
        #"\b(is|are)\s+at\s+\d"#,
        #"\b(is|are|it's|they're)\s+(now\s+)?\d+\s*(°|degrees)"#,
    ]

    /// A temperature the cook sets: an oven, a pan, oil. "Bake at 350 °F", "Preheat the oven
    /// to 425 °F", "Heat the oil to 350 °F". The number is captured.
    static let settingPattern = #"\b(oven|preheat|preheated|bake|roast|broil|heat|fry|griddle|grill|toast|set)\b[^.;]*?\b(to|at)\s+(\d+)\s*(°|degrees)"#
    /// The same, with the setting before what it is set on: "in a 350 °F oven", "a 375-degree skillet".
    static let applianceSettingPattern = #"\b(\d+)\s*-?\s*(?:°\s*f?|degrees?(?:\s*f\b)?)\s+(oven|skillet|pan|griddle|grill|oil|fryer)\b"#

    /// What a thermometer may be told to read beyond the food safety table: oil, water,
    /// sugar and milk heated to a setting.
    static let heatedLiquids = ["oil", "water", "sugar", "syrup", "milk", "caramel", "fat", "shortening"]

    static func titleProblems(_ title: String) -> [String] {
        var found: [String] = []
        if title.count > titleLimit { found.append("The title is over \(titleLimit) characters.") }
        if title.hasSuffix(".") { found.append("The title has no period.") }
        let words = title.split(separator: " ").map(String.init)
        for (wordIndex, word) in words.enumerated() {
            for (partIndex, part) in word.split(separator: "-").map(String.init).enumerated() {
                guard let first = part.first, first.isLetter else { continue }
                let isFirst = wordIndex == 0 && partIndex == 0
                if smallWords.contains(part.lowercased()) && !isFirst && partIndex == 0 {
                    if first.isUppercase { found.append("Title case keeps \"\(part.lowercased())\" lowercase: \"\(title)\".") }
                } else if !first.isUppercase {
                    found.append("The title is in title case, \"Garlic Butter Pasta\": \"\(part)\" needs a capital.")
                }
            }
        }
        return found
    }

    static func instructionProblems(_ text: String) -> [String] {
        var found: [String] = []
        if text.count > instructionLimit {
            found.append("the instruction is \(text.count) characters; at most \(instructionLimit), with the rest in \"spoken\".")
        }
        if !text.hasSuffix(".") { found.append("the instruction ends with a period.") }
        if hasTwoActions(text) {
            found.append("one action per step: the instruction gives two things to do; split it or move detail to \"spoken\".")
        }
        if matches(#"^(wait|let (it|them) (sit|rest|stand|cool))( for)?( about)? \d+( more)? (minute|minutes|hour|hours)\.?$"#,
                   in: text.lowercased()) {
            found.append("the step is only a wait; give the time as a timer on the step that starts it.")
        }
        return found
    }

    /// Words that begin a sentence telling the cook to do something: "Stir", "Add", "Bake".
    /// A sentence starting otherwise ("The edges should be golden.", "It will thicken.")
    /// only says what to look for.
    static let actionVerbs: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "braise", "bring", "broil", "brown", "brush", "chill", "chop",
        "combine", "cook", "cool", "cover", "crack", "crush", "cut", "dice", "dip", "discard", "divide",
        "drain", "drizzle", "drop", "dry", "dust", "flip", "fold", "fry", "garnish", "grate", "grease",
        "grill", "heat", "knead", "ladle", "lay", "layer", "let", "line", "lower", "marinate", "mash", "melt",
        "microwave", "mince", "mix", "peel", "place", "pour", "preheat", "press", "put", "reduce",
        "refrigerate", "remove", "rinse", "roast", "roll", "rub", "saute", "sauté", "scatter", "sear",
        "season", "serve", "set", "shake", "shape", "shred", "simmer", "slice", "spoon", "spread",
        "sprinkle", "squeeze", "steam", "stir", "strain", "stuff", "taste", "thread", "tip", "top", "toss",
        "transfer", "trim", "turn", "wash", "whisk", "wipe", "wrap",
    ]

    /// Two sentences that each tell the cook to do something ("Boil the water. Add the
    /// salt."). A second sentence that only says what to look for is fine.
    static func hasTwoActions(_ text: String) -> Bool {
        let sentences = text.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard sentences.count > 1 else { return false }
        let commands = sentences.filter { sentence in
            let first = sentence.lowercased().split(separator: " ").first.map(String.init) ?? ""
            return actionVerbs.contains(first.trimmingCharacters(in: .punctuationCharacters))
        }
        return commands.count > 1
    }

    /// Banned plain words, brand names, and claims that food is done or at a temperature.
    static func wordProblems(_ text: String) -> [String] {
        var found: [String] = []
        let lower = text.lowercased()
        for word in PlainWords.bannedWords(in: text) { found.append("\"\(word)\" is not a plain word.") }
        for brand in brands where matches(#"(^|[^a-z])"# + NSRegularExpression.escapedPattern(for: brand) + #"($|[^a-z])"#, in: lower) {
            found.append("\"\(brand)\" is a brand; name the thing instead.")
        }
        for claim in claims where matches(claim, in: lower) {
            found.append("the app never says food is done, safe or at a temperature; say what to look for.")
        }
        if matches(#"\d\s*°\s*c\b|celsius"#, in: lower) { found.append("temperatures are in °F.") }
        // A temperature is something the cook sets or measures, never a state the app claims.
        let settings = Set(settingNumbers(in: lower))
        let measured = lower.contains("thermometer")
        let liquid = heatedLiquids.contains { matches(#"\b"# + $0 + #"\b"#, in: lower) }
        for degrees in numbers(#"(\d+)\s*(°|degrees)"#, in: lower) where !settings.contains(degrees) {
            if !(measured && (FoodSafety.temperatures.contains(degrees) || liquid)) {
                found.append("\(degrees) °F: a temperature is a setting (\"Bake at 350 °F.\") or what a thermometer should read, a safe temperature from the food safety table.")
            }
        }
        return found
    }

    /// The temperatures the text sets: "Bake at 350 °F" gives 350.
    static func settingNumbers(in lower: String) -> [Int] {
        let range = NSRange(lower.startIndex..., in: lower)
        let set = RegexCache.shared.regex(settingPattern).map { regex in
            regex.matches(in: lower, range: range).compactMap { match in
                Range(match.range(at: 3), in: lower).flatMap { Int(lower[$0]) }
            }
        } ?? []
        let named = RegexCache.shared.regex(applianceSettingPattern).map { regex in
            regex.matches(in: lower, range: range).compactMap { match in
                Range(match.range(at: 1), in: lower).flatMap { Int(lower[$0]) }
            }
        } ?? []
        return set + named
    }

    /// A time a step names: the minutes it says (a range's upper number), and the timer
    /// lengths that cover it (a range's lower number too).
    struct StatedTime: Equatable, Sendable {
        let minutes: Int
        let covered: Set<Int>
    }

    /// Every time the text names, in minutes; hours count 60 each. "7 to 10 minutes" is one
    /// time, covered by a 7- or a 10-minute timer. Under a minute needs no timer ("30
    /// seconds", "1/2 minute"); seconds count only as whole minutes ("120 seconds").
    static func statedTimes(in text: String) -> [StatedTime] {
        let lower = text.lowercased()
        let pattern = #"(?<![\d/])(?:(\d+)\s*(?:to|-|–|or)\s*)?(\d+)(?![\d/])\s*(?:more\s+)?(minutes|minute|min|hours|hour|hr|seconds|second|sec)\b"#
        guard let regex = RegexCache.shared.regex(pattern) else { return [] }
        return regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).compactMap { match in
            let number: (Int) -> Int? = { Range(match.range(at: $0), in: lower).flatMap { Int(lower[$0]) } }
            guard let upper = number(2), let unitRange = Range(match.range(at: 3), in: lower) else { return nil }
            let unit = lower[unitRange]
            let toMinutes: (Int) -> Int?
            if unit.hasPrefix("h") {
                toMinutes = { $0 * 60 }
            } else if unit.hasPrefix("s") {
                toMinutes = { $0 >= 60 && $0 % 60 == 0 ? $0 / 60 : nil }
            } else {
                toMinutes = { $0 }
            }
            guard let minutes = toMinutes(upper) else { return nil }
            let low = number(1).flatMap(toMinutes)
            return StatedTime(minutes: minutes, covered: Set([minutes] + (low.map { [$0] } ?? [])))
        }
    }

    /// Every number of minutes the text names: each time's upper number.
    static func statedMinutes(in text: String) -> [Int] { statedTimes(in: text).map(\.minutes) }

    /// The screen and the spoken text never disagree on a number. Every number the screen
    /// shows is said too (as digits, or a word up to twenty: "5 minutes" may be "five minutes").
    /// The spoken text may add what doesn't fit on screen, an amount to measure or a range's
    /// upper end ("Cook 3 minutes." / "Cook 3 to 4 minutes."), but never a time or a
    /// temperature the screen leaves out.
    static func numberProblems(shown: String, spoken: String) -> [String] {
        var found: [String] = []
        let shownNumbers = digitRuns(in: shown)
        let said = Set(digitRuns(in: spoken)).union(wordNumbers(in: spoken))
        var reported: Set<String> = []
        for number in shownNumbers where !said.contains(number) && reported.insert(number).inserted {
            found.append("the screen says \(number) but \"spoken\" doesn't; say every number the screen shows.")
        }
        let lower = spoken.lowercased()
        let words = numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let pattern = #"(?<![\d/.])(\d+)(?:\s*(?:to|-|–|or)\s*(?:\d+|"# + words + #"))?\s*(?:more\s+)?((?:minutes|minute|mins|min|hours|hour|hrs|hr|seconds|second|secs|sec|degrees)\b|°)"#
        guard let regex = RegexCache.shared.regex(pattern) else { return found }
        let onScreen = Set(shownNumbers)
        for match in regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            guard let numberRange = Range(match.range(at: 1), in: lower),
                  let unitRange = Range(match.range(at: 2), in: lower) else { continue }
            let number = String(lower[numberRange])
            guard !onScreen.contains(number) else { continue }
            let unit = lower[unitRange]
            let what = unit == "°" || unit == "degrees" ? "\(number) °F" : "\(number) \(unit)"
            found.append("\"spoken\" says \(what) but the screen doesn't; a time or temperature goes on the screen too (spoken may add only a range's upper end or an amount to measure).")
        }
        return found
    }

    /// Every run of digits: "1 1/2 cups" gives 1, 1, 2.
    static func digitRuns(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isASCII || !$0.isNumber }).map(String.init)
    }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20,
    ]

    /// The numbers said as words, as digits: "five minutes" gives 5.
    private static func wordNumbers(in text: String) -> Set<String> {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter })
        return Set(words.compactMap { numberWords[String($0)].map(String.init) })
    }

    static func isOffTheHeat(_ text: String) -> Bool {
        let lower = text.lowercased()
        return offHeatWords.contains { matches(#"\b"# + $0 + #"\b"#, in: lower) }
    }

    static func addsSomething(_ instruction: String) -> Bool {
        let lower = instruction.lowercased()
        return addingStarts.contains { lower.hasPrefix($0 + " ") }
    }

    /// Nil when `amount` is a number, or "a", with an optional size and a US kitchen unit:
    /// "4", "1 1/2 cups", "a pinch", "2 large", "to taste".
    static func amountProblem(_ amount: String) -> String? {
        let lower = amount.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty { return "it needs an amount, like \"1 cup\" or \"2\"." }
        if lower == "to taste" { return nil }
        var tokens = lower.split(separator: " ").map(String.init)
        let isNumber: (String) -> Bool = { matches(#"^\d+(/\d+)?(-\d+(/\d+)?)?$"#, in: $0) }
        guard let first = tokens.first, isNumber(first) || first == "a" || first == "an" else {
            return "the amount starts with a number or \"a\": \"\(amount)\"."
        }
        tokens.removeFirst()
        if first == "a", tokens.first == "few" || tokens.first == "couple" {   // "a few dashes"
            tokens.removeFirst()
            if tokens.first == "of" { tokens.removeFirst() }
            guard !tokens.isEmpty else { return "\"\(amount)\" names no unit." }
        }
        if let next = tokens.first, isNumber(next), next.contains("/") { tokens.removeFirst() } // "1 1/2"
        if let next = tokens.first, sizes.contains(next) { tokens.removeFirst() }
        if tokens.isEmpty { return isNumber(first) || lower.split(separator: " ").count > 1 ? nil : "\"\(amount)\" names no unit." }
        let unit = tokens.joined(separator: " ")
        if isUnit(unit) { return nil }
        return "use US kitchen units (cup, tablespoon, teaspoon, pound, ounce...), and put words like \"minced\" in the name: \"\(amount)\"."
    }

    static func isUnit(_ word: String) -> Bool {
        units.contains(word) || (word.hasSuffix("es") && units.contains(String(word.dropLast(2))))
            || (word.hasSuffix("s") && units.contains(String(word.dropLast())))
            || (word.hasSuffix("ves") && units.contains(String(word.dropLast(3)) + "f")) // leaves, loaves
    }

    /// Whether a step names the ingredient: its name before any comma, or that name's
    /// last word ("long-grain white rice" is used by "the rice"), plurals forgiven.
    static func isUsed(_ name: String, in steps: String) -> Bool {
        let core = mainName(name)
        let lower = steps.lowercased()
        if core.isEmpty { return false }
        if lower.contains(core) { return true }
        guard let last = core.split(whereSeparator: { $0 == " " || $0 == "-" }).last.map(String.init) else { return false }
        let stems = [last, last.hasSuffix("es") ? String(last.dropLast(2)) : last, last.hasSuffix("s") ? String(last.dropLast()) : last]
        return stems.contains { $0.count >= 3 && matches(#"\b"# + NSRegularExpression.escapedPattern(for: $0), in: lower) }
    }

    /// An ingredient's main name: the text before the first comma, any parentheses taken
    /// out. "tomatoes (canned), drained" is "tomatoes".
    static func mainName(_ name: String) -> String {
        let plain = name.lowercased().replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        let core = plain.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return core.split(separator: " ").joined(separator: " ")
    }

    // MARK: Helpers

    static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = RegexCache.shared.regex(pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The first captured number of every match.
    static func numbers(_ pattern: String, in text: String) -> [Int] {
        guard let regex = RegexCache.shared.regex(pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }
}

extension RecipeBook {
    /// The fields a file may have, by where they sit. Anything else is a typo.
    static let allowedKeys: [String: Set<String>] = [
        "recipe": ["id", "title", "category", "method", "source", "serves", "totalMinutes", "ingredients", "steps"],
        "source": ["name", "url", "credit"],
        "ingredient": ["amount", "name"],
        "step": ["instruction", "spoken", "watch", "cue", "timer"],
        "watch": ["ingredient", "timerLabel", "timerMinutes", "minimumChange", "countsRelease"],
        "cue": ["timerLabel", "secondsLeft"],
        "timer": ["label", "minutes"],
    ]

    /// Every problem with the recipe files in `folder`, one line each, starting with the
    /// file's name. Empty means the whole book is fine.
    static func check(folder: URL) -> [String] {
        checkReport(folder: folder).lines
    }

    /// What the checker found: how many files, which failed, and failures counted by rule.
    struct CheckReport: Equatable, Sendable {
        var files = 0
        var failedFiles: Set<String> = []
        var lines: [String] = []
        /// Each rule's short name and how many problems broke it, most first.
        var byRule: [(rule: String, count: Int)] {
            var counts: [String: Int] = [:]
            for line in lines { counts[RecipeBook.rule(of: line), default: 0] += 1 }
            return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { ($0.key, $0.value) }
        }
        var passed: Int { files - failedFiles.count }

        /// The closing lines: files, passed, failed, then failures by rule.
        var summary: [String] {
            var out = ["\(files) files, \(passed) passed, \(failedFiles.count) failed."]
            out += byRule.map { "  \($0.count) × \($0.rule)" }
            return out
        }

        static func == (a: CheckReport, b: CheckReport) -> Bool {
            a.files == b.files && a.failedFiles == b.failedFiles && a.lines == b.lines
        }
    }

    /// Files in the recipe folder that are not recipes.
    static let indexFile = "index.json"
    /// A converter's top-level note on a held recipe: the checker skips it, adding drops it.
    static let heldKey = "_held"
    static let sourcesFile = "sources.json"

    /// Checks every recipe file in `folder`, or only the slugs in `only`. Titles and ids are
    /// checked as unique against the whole folder either way, and every outside source must
    /// have its credit in `sources.json`.
    static func checkReport(folder: URL, only: Set<String>? = nil) -> CheckReport {
        var report = CheckReport()
        let all = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != indexFile && $0 != sourcesFile }.sorted()
        if all.isEmpty {
            report.lines = ["\(folder.path): no recipe files here."]
            return report
        }
        let names = only.map { wanted in all.filter { wanted.contains(String($0.dropLast(5))) } } ?? all
        if let only {
            let found = Set(names.map { String($0.dropLast(5)) })
            for slug in only.subtracting(found).sorted() {
                report.lines.append("\(slug).json: no such file in \(folder.path).")
                report.failedFiles.insert(slug + ".json")
            }
        }
        report.files = names.count
        let checked = Set(names)
        let sources = Self.sources(in: folder)
        var seenTitles: [String: String] = [:]
        var seenIDs: [String: String] = [:]
        // Every file is read once; only the chosen ones get the full rules.
        for name in all {
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else { continue }
            let full = checked.contains(name)
            var lines: [String] = []
            if full { lines += unknownKeys(in: data).map { "\(name): \($0)" } }
            switch decode(data) {
            case .failure(let error):
                if full { lines.append("\(name): \(error.text)") }
            case .success(let recipe):
                if let other = seenTitles[recipe.title.lowercased()] {
                    if full || checked.contains(other) { lines.append("\(name): the title \"\(recipe.title)\" is already used by \(other).") }
                } else { seenTitles[recipe.title.lowercased()] = name }
                if let other = seenIDs[recipe.id] {
                    if full || checked.contains(other) { lines.append("\(name): the id \"\(recipe.id)\" is already used by \(other).") }
                } else { seenIDs[recipe.id] = name }
                guard full else { break }
                if name != recipe.id + ".json" { lines.append("\(name): the file name must be the id: \(recipe.id).json.") }
                if !matches(recipe.id) { lines.append("\(name): the id is lowercase words joined by hyphens, like \"garlic-butter-pasta\".") }
                if !recipe.source.isOwn && !sources.contains(where: { $0.name == recipe.source.name }) {
                    lines.append("\(name): the source \"\(recipe.source.name)\" needs its credit in sources.json.")
                }
                lines += recipe.authoringProblems().map { "\(name): \($0)" }
            }
            if !lines.isEmpty { report.failedFiles.insert(name) }
            report.lines += lines
        }
        return report
    }

    /// A problem line's rule, for the summary: the words with the file, step, quoted text and
    /// numbers taken out, up to the first semicolon or colon.
    static func rule(of line: String) -> String {
        var text = line
        if let colon = text.range(of: ": ") { text = String(text[colon.upperBound...]) }
        if text.hasPrefix("Step "), let colon = text.range(of: ": ") { text = String(text[colon.upperBound...]) }
        if text.hasPrefix("Ingredient "), let quote = text.range(of: "\" ", options: .backwards) ?? text.range(of: "\": ") {
            text = String(text[quote.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        }
        text = text.replacingOccurrences(of: #""[^"]*""#, with: "…", options: .regularExpression)
            .replacingOccurrences(of: #"\d+"#, with: "N", options: .regularExpression)
        if let stop = text.firstIndex(where: { $0 == ";" || $0 == ":" || $0 == "(" }) { text = String(text[..<stop]) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    private static func matches(_ id: String) -> Bool {
        RecipeRules.matches(#"^[a-z0-9]+(-[a-z0-9]+)*$"#, in: id)
    }

    /// Fields the format doesn't have, like "spokn" for "spoken".
    static func unknownKeys(in data: Data) -> [String] {
        guard let recipe = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var found: [String] = []
        func check(_ object: Any?, as kind: String, at place: String) {
            guard let object = object as? [String: Any], let allowed = allowedKeys[kind] else { return }
            for key in object.keys.sorted() where !allowed.contains(key) {
                found.append("unknown field \"\(key)\"\(place); allowed: \(allowed.sorted().joined(separator: ", ")).")
            }
        }
        // "_held" is a converter's note on a recipe held aside; adding drops it.
        check(recipe.filter { $0.key != heldKey }, as: "recipe", at: "")
        check(recipe["source"], as: "source", at: " in source")
        for (index, item) in ((recipe["ingredients"] as? [Any]) ?? []).enumerated() {
            check(item, as: "ingredient", at: " in ingredient \(index + 1)")
        }
        for (index, step) in ((recipe["steps"] as? [Any]) ?? []).enumerated() {
            check(step, as: "step", at: " in step \(index + 1)")
            let fields = step as? [String: Any]
            check(fields?["watch"], as: "watch", at: " in step \(index + 1) watch")
            check(fields?["cue"], as: "cue", at: " in step \(index + 1) cue")
            check(fields?["timer"], as: "timer", at: " in step \(index + 1) timer")
        }
        return found
    }
}

/// Compiled patterns, kept: the checker runs the same few dozen over every line of a
/// thousand recipes, and compiling each time was most of its run time.
final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()
    private let lock = NSLock()
    private var compiled: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let regex = compiled[pattern] { return regex }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        compiled[pattern] = regex
        return regex
    }
}
