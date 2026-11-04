import AVFoundation
import SwiftUI

/// Settings, from the bar or "settings": one column of rows, each saying what it is, how
/// it is now, the phrase that changes it, and a word button that does the same.
struct SettingsScreen: View {
    let session: CookSession

    var body: some View {
        MenuScreen(session: session, title: "Settings") {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: Theme.gap, verticalSpacing: 0) {
                    row("Recipe", now: "\(session.recipe.title), step \(session.stepIndex + 1)", button: "Restart",
                        say: "start over") {
                        // Back to the cook screen at step 1, with this recipe's timers cleared.
                        session.restartRecipe()
                    }
                    rule
                    let on = session.cameraOn
                    row("Camera", now: on ? "On" : "Off", button: on ? "Turn off" : "Turn on",
                        say: on ? "turn off the camera" : "turn on the camera") {
                        session.setCamera(on: !on)
                    }
                    rule
                    let front = session.cameraPosition == .front
                    row("Camera side", now: front ? "Front" : "Back", button: front ? "Use back" : "Use front",
                        say: front ? "use the back camera" : "use the front camera", enabled: on) {
                        Task { await session.flipCamera() }
                    }
                    rule
                    let marked = session.region != nil
                    row("Pan", now: marked ? "Marked" : "Not marked", button: marked ? "Draw again" : "Draw it",
                        say: "draw the pan again", enabled: on) {
                        // Drawing happens on the cook screen, cleared to the picture.
                        session.open(.cook)
                        session.markPan()
                    }
                    rule
                    row("Speaks", now: session.voiceOn ? "On" : "Quiet", button: session.voiceOn ? "Go quiet" : "Talk",
                        say: session.voiceOn ? "be quiet" : "talk to me") {
                        session.voiceOn.toggle()
                    }
                    rule
                    row("Voice", now: voiceName, button: "Change", say: "change the voice") {
                        session.open(.voices)
                    }
                    rule
                    let listening = session.listeningOn
                    row("Listening", now: listening ? "On" : "Off", button: listening ? "Pause" : "Listen",
                        say: listening ? "stop listening" : nil) {
                        // A pause lasts 2 minutes, like "stop listening"; Listen ends it.
                        if listening {
                            session.pauseListening()
                        } else {
                            session.toggleListening()
                        }
                    }
                    rule
                    let shown = session.showDebug
                    row("Details", now: shown ? "Shown" : "Hidden", button: shown ? "Hide" : "Show",
                        say: shown ? "hide the details" : "show the details") {
                        // The panel, with the practice recorder in it, sits beside the cook screen.
                        session.showDebug = !shown
                        if !shown { session.open(.cook) }
                    }
                    rule
                    row("What can I say", now: nil, button: "Open", say: "help") {
                        session.showHelp()
                    }
                }
            }
        }
    }

    /// The name of the voice that speaks now: the one chosen, or the best on the phone.
    private var voiceName: String {
        Speaker.voice(for: session.voiceID)?.name ?? "System"
    }

    private var rule: some View {
        RowRule()
            .gridCellUnsizedAxes(.horizontal)
    }

    /// Name, how it is now, the phrase, and the button, in four aligned columns. Rows are
    /// 60 pt and buttons 44 pt, which leaves 16 pt between buttons in neighboring rows.
    private func row(
        _ name: String, now: String?, button word: String, say phrase: String?, enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        GridRow(alignment: .center) {
            Text(name)
                .font(Theme.control)
                .foregroundStyle(enabled ? Theme.flour : Theme.ash)
                .frame(minHeight: Theme.bigTarget)
            Text(now ?? "")
                .font(Theme.control)
                .foregroundStyle(Theme.ash)
            Text(phrase.map { "Say \u{201C}\($0)\u{201D}" } ?? "")
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityHidden(phrase == nil)
            Button {
                session.noteTouch()
                action()
            } label: {
                Text(word).frame(maxWidth: .infinity)
            }
            .buttonStyle(WordButtonStyle(height: Theme.target))
            .disabled(!enabled)
            .accessibilityLabel("\(name): \(word)")
        }
    }
}
