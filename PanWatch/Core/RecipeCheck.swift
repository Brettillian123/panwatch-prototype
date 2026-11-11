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
        }
        return found
    }

    /// Everything `problems()` finds, plus the rules for writing a recipe for the book
    /// (`Recipes/README.md`): sizes, wording, units, timers and the camera.
    func authoringProblems() -> [String] {
        var found = problems()
        found += RecipeRules.titleProblems(title)
        if !(1...12).contains(serves) { found.append("\"serves\" must be 1 to 12; it is \(serves).") }
        if !(1...240).contains(totalMinutes) { found.append("\"totalMinutes\" must be 1 to 240; it is \(totalMinutes).") }
        let timed = steps.reduce(0) { $0 + ($1.watch?.timerMinutes ?? 0) + ($1.timer?.minutes ?? 0) }
        if totalMinutes < timed {
            found.append("\"totalMinutes\" is \(totalMinutes), less than its timers add up to (\(timed)).")
        }
        if !(3...12).contains(steps.count) { found.append("A recipe has 3 to 12 steps; this one has \(steps.count).") }
        if !source.isOwn && !source.url.hasPrefix("https://") {
            found.append("A recipe from elsewhere needs the source's \"url\", starting https://.")
        }

        let timerMinutes = Set(steps.compactMap(\.watch?.timerMinutes) + steps.compactMap(\.timer?.minutes))
        for step in steps {
            let name = "Step \(step.id)"
            found += RecipeRules.instructionProblems(step.instruction).map { "\(name): \($0)" }
            for text in [step.instruction, step.spoken].compactMap({ $0 }) {
                found += RecipeRules.wordProblems(text).map { "\(name): \($0)" }
                for minutes in RecipeRules.statedMinutes(in: text) where !timerMinutes.contains(minutes)
                    && !RecipeRules.isOffTheHeat(text) {
                    found.append("\(name): it says \(minutes) minutes, but no step has a \(minutes)-minute timer.")
                }
            }
            if let watch = step.watch {
                if !method.cameraCanHelp {
                    found.append("\(name): only pot and pan recipes have a \"watch\"; this one is \(method.rawValue).")
                } else if !RecipeRules.addsSomething(step.instruction) {
                    found.append("\(name): a \"watch\" belongs on a step that adds something to the pot or pan (Add, Stir in, Lower, Lay...).")
                }
                if watch.timerMinutes > 120 { found.append("\(name): a watch timer runs 1 to 120 minutes.") }
                found += RecipeRules.wordProblems(watch.ingredient + " " + watch.timerLabel).map { "\(name): \($0)" }
            }
            if let timer = step.timer {
                if !(1...240).contains(timer.minutes) { found.append("\(name): a timer runs 1 to 240 minutes.") }
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

    /// Words a title keeps lowercase unless they come first: "Chicken with Rice".
    static let smallWords: Set<String> = ["a", "an", "and", "the", "of", "with", "in", "on", "or", "for", "to", "at", "by"]

    /// US kitchen units, singular; a plural "s" or "es" is fine too.
    static let units: Set<String> = [
        "cup", "tablespoon", "teaspoon", "pound", "ounce", "fluid ounce", "quart", "pint", "gallon",
        "clove", "pinch", "dash", "can", "jar", "stick", "slice", "piece", "bunch", "head", "sprig",
        "stalk", "ear", "inch", "bowl", "handful", "package", "bag", "box", "leaf", "loaf",
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
    ]

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
        if matches(#"[.!?;]\s+\S"#, in: text) {
            found.append("one action per step: the instruction is one sentence; split it or move detail to \"spoken\".")
        }
        if matches(#"^(wait|let (it|them) (sit|rest|stand|cool))( for)?( about)? \d+( more)? (minute|minutes|hour|hours)\.?$"#,
                   in: text.lowercased()) {
            found.append("the step is only a wait; give the time as a timer on the step that starts it.")
        }
        return found
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
        for degrees in numbers(#"(\d+)\s*(°|degrees)"#, in: lower) {
            let oven = lower.contains("oven") || lower.contains("preheat")
            if !oven && !(FoodSafety.temperatures.contains(degrees) && lower.contains("thermometer")) {
                found.append("\(degrees) °F: a temperature is an oven setting, or a safe temperature from the food safety table checked with a thermometer.")
            }
        }
        return found
    }

    /// Every number of minutes the text names; hours count as 60 minutes each.
    static func statedMinutes(in text: String) -> [Int] {
        let lower = text.lowercased()
        return numbers(#"(\d+)\s*(more\s+)?(minute|minutes|min)\b"#, in: lower)
            + numbers(#"(\d+)\s*(more\s+)?(hour|hours)\b"#, in: lower).map { $0 * 60 }
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
        let core = name.lowercased().split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let lower = steps.lowercased()
        if core.isEmpty { return false }
        if lower.contains(core) { return true }
        guard let last = core.split(whereSeparator: { $0 == " " || $0 == "-" }).last.map(String.init) else { return false }
        let stems = [last, last.hasSuffix("es") ? String(last.dropLast(2)) : last, last.hasSuffix("s") ? String(last.dropLast()) : last]
        return stems.contains { $0.count >= 3 && matches(#"\b"# + NSRegularExpression.escapedPattern(for: $0), in: lower) }
    }

    // MARK: Helpers

    static func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The first captured number of every match.
    static func numbers(_ pattern: String, in text: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) }
        }
    }
}

extension RecipeBook {
    /// The fields a file may have, by where they sit. Anything else is a typo.
    static let allowedKeys: [String: Set<String>] = [
        "recipe": ["id", "title", "category", "method", "source", "serves", "totalMinutes", "ingredients", "steps"],
        "source": ["name", "url"],
        "ingredient": ["amount", "name"],
        "step": ["instruction", "spoken", "watch", "cue", "timer"],
        "watch": ["ingredient", "timerLabel", "timerMinutes", "minimumChange", "countsRelease"],
        "cue": ["timerLabel", "secondsLeft"],
        "timer": ["label", "minutes"],
    ]

    /// Every problem with the recipe files in `folder`, one line each, starting with the
    /// file's name. Empty means the whole book is fine.
    static func check(folder: URL) -> [String] {
        var lines: [String] = []
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        if names.isEmpty { return ["\(folder.path): no recipe files here."] }
        var fileOf: [String: String] = [:]
        for name in names {
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path) else { continue }
            lines += unknownKeys(in: data).map { "\(name): \($0)" }
            switch decode(data) {
            case .failure(let error):
                lines.append("\(name): \(error.text)")
            case .success(let recipe):
                fileOf[recipe.id] = name
                if name != recipe.id + ".json" { lines.append("\(name): the file name must be the id: \(recipe.id).json.") }
                if !matches(recipe.id) { lines.append("\(name): the id is lowercase words joined by hyphens, like \"garlic-butter-pasta\".") }
                lines += recipe.authoringProblems().map { "\(name): \($0)" }
            }
        }
        // Titles and ids are unique across the book.
        let loaded = names.compactMap { name -> (String, Recipe)? in
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(name).path),
                  case .success(let recipe) = decode(data) else { return nil }
            return (name, recipe)
        }
        var seenTitles: [String: String] = [:]
        var seenIDs: [String: String] = [:]
        for (name, recipe) in loaded {
            if let other = seenTitles[recipe.title.lowercased()] {
                lines.append("\(name): the title \"\(recipe.title)\" is already used by \(other).")
            } else { seenTitles[recipe.title.lowercased()] = name }
            if let other = seenIDs[recipe.id] {
                lines.append("\(name): the id \"\(recipe.id)\" is already used by \(other).")
            } else { seenIDs[recipe.id] = name }
        }
        return lines
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
        check(recipe, as: "recipe", at: "")
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
