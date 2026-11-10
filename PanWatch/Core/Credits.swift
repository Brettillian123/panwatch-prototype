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
}
