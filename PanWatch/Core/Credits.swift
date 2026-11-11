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

    /// One notice per outside source of recipes, naming the dishes adapted from it, for
    /// Profile > Advanced > About. The app's own recipes need none.
    static func recipeNotices(_ recipes: [Recipe] = Recipe.all) -> [Notice] {
        var order: [String] = []
        var bySource: [String: [Recipe]] = [:]
        for recipe in recipes where !recipe.source.isOwn {
            if bySource[recipe.source.name] == nil { order.append(recipe.source.name) }
            bySource[recipe.source.name, default: []].append(recipe)
        }
        return order.map { name in
            let dishes = bySource[name] ?? []
            let lines = dishes.map { "\($0.displayTitle), adapted from \($0.source.url)" }
            return Notice(title: "Recipes from \(name)", text: lines.joined(separator: "\n"))
        }
    }
}
