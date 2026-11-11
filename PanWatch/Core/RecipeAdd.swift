import Foundation

/// Adding a batch of recipe files to the book in one step: check them all against the book,
/// copy them into `Recipes/`, credit any new source, and repack.
extension RecipeBook {
    struct AddResult: Sendable {
        /// Every problem found, one line each; nothing was changed when there is any.
        var problems: [String] = []
        var added: [Recipe] = []
        var newSources: [RecipeSourceCredit] = []
        /// The whole book after adding.
        var book: [Recipe] = []

        /// The closing lines: added, total, then per category (added, total).
        var summary: [String] {
            guard problems.isEmpty else { return ["Nothing added: \(problems.count) problem\(problems.count == 1 ? "" : "s")."] }
            var out = ["Added \(added.count) recipes; the book has \(book.count)."]
            for category in RecipeCategory.allCases {
                let total = book.filter { $0.category == category }.count
                guard total > 0 else { continue }
                let new = added.filter { $0.category == category }.count
                out.append("  \(category.title): \(total)" + (new > 0 ? " (+\(new))" : ""))
            }
            out += newSources.map { "  New source credited: \($0.name)" }
            return out
        }
    }

    /// Adds every recipe file in `incoming` to the sources in `book` and rewrites the packed
    /// files in `packed`, or changes nothing and lists every problem: a file the full checker
    /// refuses, or an id or title already in the book.
    static func add(from incoming: URL, book: URL, packed: URL, assets: URL?) -> AddResult {
        var result = AddResult()
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: incoming.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != indexFile && $0 != sourcesFile }.sorted()
        guard !names.isEmpty else {
            result.problems = ["\(incoming.path): no recipe files here."]
            return result
        }
        let bookNames = Set(((try? fm.contentsOfDirectory(atPath: book.path)) ?? []).filter { $0.hasSuffix(".json") })
        let staging = fm.temporaryDirectory.appendingPathComponent("recipe-add-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for name in bookNames where name != sourcesFile {
                try fm.copyItem(at: book.appendingPathComponent(name), to: staging.appendingPathComponent(name))
            }
        } catch {
            result.problems = ["Could not stage the book: \(error.localizedDescription)"]
            return result
        }

        // The batch beside the book, and a credit for each outside source the book lacks.
        var credits = sources(in: book)
        var checked: Set<String> = []
        for name in names {
            if bookNames.contains(name) {
                result.problems.append("\(name): already in the book as Recipes/\(name).")
                continue
            }
            let from = incoming.appendingPathComponent(name)
            try? fm.copyItem(at: from, to: staging.appendingPathComponent(name))
            checked.insert(String(name.dropLast(5)))
            guard let data = fm.contents(atPath: from.path), case .success(let recipe) = decode(data),
                  !recipe.source.isOwn, !credits.contains(where: { $0.name == recipe.source.name }) else { continue }
            let credit = RecipeSourceCredit(name: recipe.source.name, credit: "Recipes adapted from \(recipe.source.name).",
                                            url: origin(of: recipe.source.url))
            credits.append(credit)
            result.newSources.append(credit)
        }
        let creditData = encodeSources(credits)
        try? creditData.write(to: staging.appendingPathComponent(sourcesFile))
        result.problems += checkReport(folder: staging, only: checked).lines
        guard result.problems.isEmpty else {
            result.newSources = []
            return result
        }

        do {
            for name in names {
                try fm.copyItem(at: incoming.appendingPathComponent(name), to: book.appendingPathComponent(name))
            }
            if !result.newSources.isEmpty { try creditData.write(to: book.appendingPathComponent(sourcesFile)) }
            try writePack(sources: book, assets: assets, to: packed)
        } catch {
            result.problems = ["Could not write the book: \(error.localizedDescription)"]
            return result
        }
        result.book = load(from: book).recipes
        result.added = result.book.filter { checked.contains($0.id) }
        return result
    }

    /// `sources.json`'s text: one credit per line, keys sorted.
    static func encodeSources(_ credits: [RecipeSourceCredit]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = credits.compactMap { (try? encoder.encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
        return Data((lines.isEmpty ? "[]\n" : "[\n" + lines.joined(separator: ",\n") + "\n]\n").utf8)
    }

    /// "https://www.seriouseats.com/" for any page on that site; the link itself if it has
    /// no host.
    static func origin(of link: String) -> String {
        guard let url = URL(string: link), let scheme = url.scheme, let host = url.host else { return link }
        return "\(scheme)://\(host)/"
    }
}
