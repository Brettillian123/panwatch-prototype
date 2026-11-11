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
    /// The app's own recipes need none.
    static func recipeNotices(_ entries: [RecipeEntry] = RecipeIndex.bundled.entries,
                              sources: [RecipeSourceCredit] = RecipeBook.bundledFolder().map(RecipeBook.sources(in:)) ?? []) -> [Notice] {
        var seen: Set<String> = []
        var notices: [Notice] = []
        for entry in entries where entry.source != RecipeSource.own.name && !seen.contains(entry.source) {
            seen.insert(entry.source)
            let credit = sources.first { $0.name == entry.source }
            let text = credit.map { $0.credit + "\n" + $0.url } ?? "Recipes adapted from \(entry.source)."
            notices.append(Notice(title: entry.source, text: text))
        }
        return notices
    }
}
