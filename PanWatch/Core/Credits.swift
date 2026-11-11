import Foundation

/// The notices the app's voice models and libraries ask for, shown under Settings > Credits.
enum Credits {
    struct Notice: Equatable, Identifiable, Sendable {
        let title: String
        let text: String
        var id: String { title }
    }

    /// Pocket TTS is CC-BY-4.0, which needs the creator, the license with a link, and a
    /// note of changes. Kokoro and FluidAudio are Apache 2.0.
    static let notices: [Notice] = [
        Notice(
            title: "Pocket TTS",
            text: "Your recorded voice is spoken with Pocket TTS by Kyutai (huggingface.co/kyutai/pocket-tts), "
                + "licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0). "
                + "Converted to Core ML by FluidInference (huggingface.co/FluidInference/pocket-tts-coreml)."
        ),
        Notice(
            title: "Kokoro",
            text: "Natural voices use Kokoro-82M by hexgrad (huggingface.co/hexgrad/Kokoro-82M), "
                + "licensed under the Apache License 2.0 (apache.org/licenses/LICENSE-2.0)."
        ),
        Notice(
            title: "FluidAudio",
            text: "On-phone speech runs on FluidAudio by FluidInference (github.com/FluidInference/FluidAudio), "
                + "licensed under the Apache License 2.0 (apache.org/licenses/LICENSE-2.0)."
        ),
    ]

    /// One notice per outside source of recipes, each source once in book order, with its
    /// credit line and link from `Recipes/sources.json`, for Profile > Advanced > About.
    /// The app's own recipes need none. Under each source, the programs or authors its
    /// recipes credit (`source.credit`), each once, in book order.
    static func recipeNotices(_ entries: [RecipeEntry] = RecipeIndex.bundled.entries,
                              sources: [RecipeSourceCredit] = RecipeBook.bundledSources()) -> [Notice] {
        var order: [String] = []
        var credited: [String: [String]] = [:]
        for entry in entries where entry.source != RecipeSource.own.name {
            if credited[entry.source] == nil { order.append(entry.source); credited[entry.source] = [] }
            if let credit = entry.credit, !credit.isEmpty, credited[entry.source]?.contains(credit) == false {
                credited[entry.source]?.append(credit)
            }
        }
        return order.map { name in
            let source = sources.first { $0.name == name }
            var text = source.map { $0.credit + "\n" + $0.url } ?? "Recipes adapted from \(name)."
            for credit in credited[name] ?? [] { text += "\n" + credit }
            return Notice(title: name, text: text)
        }
    }
}
