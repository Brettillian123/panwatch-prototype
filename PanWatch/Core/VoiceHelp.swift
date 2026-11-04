import Foundation

/// The whole voice grammar as the help screen lists it: one or two phrases for each command,
/// grouped the way a cook thinks of them. Every phrase here is one the parser understands.
enum HelpGroup: String, CaseIterable, Sendable {
    case steps, timers, offer, recipes, camera, voice, menus

    var title: String {
        switch self {
        case .steps: "Steps"
        case .timers: "Timers"
        case .offer: "Offers"
        case .recipes: "Recipes"
        case .camera: "Camera"
        case .voice: "Voice"
        case .menus: "Menus"
        }
    }

    var phrases: [String] {
        switch self {
        case .steps: ["next step", "back", "repeat", "step three", "where am I", "ingredients", "start over", "skip"]
        case .timers: ["start the timer", "five minute timer", "how long", "cancel the timer", "cancel the pasta timer", "clear it"]
        case .offer: ["yes", "not now"]
        case .recipes: ["recipes", "make the rice", "let's do pasta"]
        case .camera: ["mark the pan", "bigger", "smaller", "start watching", "turn off the camera", "use the front camera", "check the setup"]
        case .voice: ["change the voice", "try Samantha", "use Samantha", "next voice", "use my voice", "be quiet", "talk to me", "stop listening"]
        case .menus: ["settings", "show the details", "record a practice", "that was it", "what can I say", "done"]
        }
    }

    /// The groups in the order the help screen shows them: the ones `screen` is about first.
    static func ordered(for screen: AppScreen) -> [HelpGroup] {
        let first: [HelpGroup] = switch screen {
        case .cook, .help: []
        case .recipes: [.recipes]
        case .settings: [.camera, .voice, .menus]
        case .voices: [.voice]
        }
        return first + allCases.filter { !first.contains($0) }
    }
}
