import Foundation
@testable import PanWatchCore

// The recipe book's commands, run from the repo root:
//   swift run -c release PanWatchScenarios --add-recipes <folder>
//     Checks every file in <folder> with the full checker against the book, and refuses the
//     whole folder (listing each problem) if any fails or an id or title is already in the
//     book. Otherwise copies them into Recipes/, credits new sources in Recipes/sources.json,
//     rewrites the packed files in PanWatch/Core/RecipeBook/ and prints a summary.
//   swift run -c release PanWatchScenarios --check-recipes [--only slug,slug] [--pack]
//     Checks the whole book in Recipes/ and that the packed files match it exactly. --pack
//     rewrites the packed files first (when the sources pass).
//   swift run -c release PanWatchScenarios --check-recipes <folder> [--only slug,slug]
//     Checks the recipe files in <folder> as a book of their own.
// One line per problem, starting with the file's name, then a summary. Exits 1 on any problem.
enum RecipeCommands {
    static let sources = URL(fileURLWithPath: "Recipes", isDirectory: true)
    static let packed = URL(fileURLWithPath: "PanWatch/Core/" + RecipeBook.packedFolderName, isDirectory: true)
    static let assets = URL(fileURLWithPath: "PanWatch/Assets.xcassets", isDirectory: true)

    /// Runs a recipe command if the arguments name one; never returns then.
    static func runIfAsked(_ arguments: [String]) {
        if let flag = arguments.firstIndex(of: "--add-recipes") {
            guard flag + 1 < arguments.count, !arguments[flag + 1].hasPrefix("--") else {
                print("usage: --add-recipes <folder>")
                exit(2)
            }
            let started = Date()
            let result = RecipeBook.add(from: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true),
                                        book: sources, packed: packed, assets: assets)
            result.problems.forEach { print($0) }
            result.summary.forEach { print($0) }
            print(String(format: "Done in %.1f s.", Date().timeIntervalSince(started)))
            exit(result.problems.isEmpty ? 0 : 1)
        }
        guard let flag = arguments.firstIndex(of: "--check-recipes") else { return }
        let next = flag + 1 < arguments.count ? arguments[flag + 1] : ""
        let wholeBook = next.isEmpty || next.hasPrefix("--")
        let folder = wholeBook ? sources : URL(fileURLWithPath: next, isDirectory: true)
        var only: Set<String>?
        if let at = arguments.firstIndex(of: "--only"), at + 1 < arguments.count {
            only = Set(arguments[at + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasSuffix(".json") ? String($0.dropLast(5)) : $0 })
        }
        let started = Date()
        let report = RecipeBook.checkReport(folder: folder, only: only)
        report.lines.forEach { print($0) }
        report.summary.forEach { print($0) }
        var stale: [String] = []
        if wholeBook {
            if arguments.contains("--pack") || arguments.contains("--write-index") {
                if report.lines.isEmpty {
                    do {
                        try RecipeBook.writePack(sources: sources, assets: assets, to: packed)
                        print("Packed \(RecipeBook.load(from: sources).recipes.count) recipes into \(packed.relativePath).")
                    } catch {
                        print("Could not pack: \(error.localizedDescription)")
                        exit(1)
                    }
                } else {
                    print("Not packed: fix the problems first.")
                }
            }
            stale = RecipeBook.stalePackedFiles(sources: sources, assets: assets, packed: packed)
            stale.forEach { print($0) }
            print(stale.isEmpty ? "Packed files match Recipes/." : "\(stale.count) packed files out of date.")
        }
        print(String(format: "Checked in %.1f s.", Date().timeIntervalSince(started)))
        exit(report.lines.isEmpty && stale.isEmpty ? 0 : 1)
    }
}
