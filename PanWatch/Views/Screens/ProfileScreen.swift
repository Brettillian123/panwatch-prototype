import SwiftUI

/// The profile, which holds what used to be the settings: the cook's numbers when there
/// are any, then grouped rows for the camera, talking, listening, the voice, the recipe,
/// help, about and the details panel. Each still answers to the phrase it always did.
struct ProfileScreen: View {
    let session: CookSession
    @State private var confirmRestart = false
    @State private var showAbout = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space16) {
                ScreenTitle("Profile")
                stats
                GroupedRows {
                    cameraRow
                    cameraSideRow
                    panRow
                }
                GroupedRows {
                    talkRow
                    listeningRow
                }
                GroupedRows {
                    Row(label: "Voice", value: voiceName, chevron: true, action: {
                        session.noteTouch()
                        session.open(.voices)
                    })
                    speedRow
                }
                GroupedRows {
                    if session.cookUnderWay {
                        Row(label: "Restart recipe", detail: "\(session.recipe.title), step \(session.stepIndex + 1)", action: {
                            session.noteTouch()
                            confirmRestart = true
                        })
                    }
                    Row(label: "What can I say", chevron: true, action: {
                        session.noteTouch()
                        session.showHelp()
                    })
                    Row(label: "About", chevron: true, action: {
                        session.noteTouch()
                        showAbout = true
                    })
                    detailsRow
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space24)
            .screenColumn()
        }
        .scrollIndicators(.hidden)
        .confirmationDialog("Restart \(session.recipe.title)?", isPresented: $confirmRestart, titleVisibility: .visible) {
            // Back to the cook screen at step 1, with this recipe's timers cleared.
            Button("Restart", role: .destructive) { session.restartRecipe() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Back to step 1, and this recipe's timers are cleared.")
        }
        .sheet(isPresented: $showAbout) {
            AboutSheet(close: { showAbout = false })
        }
    }

    // MARK: Stats

    /// Real numbers from the usage log on this phone; nothing until the first cook.
    @ViewBuilder private var stats: some View {
        let summary = session.usage.summary
        if summary.cooks > 0 {
            Card {
                Text(statsLine(cooks: summary.cooks, commands: summary.voiceCommands))
                    .font(Theme.bodyStrong).foregroundStyle(Theme.ink).monospacedDigit()
            }
        }
    }

    private func statsLine(cooks: Int, commands: Int) -> String {
        var parts = [cooks == 1 ? "1 cook" : "\(cooks) cooks"]
        if commands > 0 { parts.append(commands == 1 ? "1 voice command" : "\(commands) voice commands") }
        return parts.joined(separator: " · ")
    }

    // MARK: Camera

    private var cameraRow: some View {
        ToggleRow(label: "Camera", detail: nil, isOn: Binding(
            get: { session.cameraOn },
            set: { on in
                session.noteTouch()
                session.setCamera(on: on)
            }
        ))
    }

    private var cameraSideRow: some View {
        let on = session.cameraOn
        return Row(label: "Camera side", value: session.cameraPosition == .front ? "Front" : "Back", action: {
            session.noteTouch()
            Task { await session.flipCamera() }
        })
        .disabled(!on)
        .opacity(on ? 1 : 0.45)
        .accessibilityHint(session.cameraPosition == .front ? "Uses the back camera" : "Uses the front camera")
    }

    private var panRow: some View {
        let on = session.cameraOn
        return Row(label: "Pan", value: session.region != nil ? "Marked" : "Not marked", chevron: true, action: {
            session.noteTouch()
            // Drawing happens on the cook screen, cleared to the picture.
            session.open(.cook)
            session.markPan()
        })
        .disabled(!on)
        .opacity(on ? 1 : 0.45)
        .accessibilityHint("Draws the pan again")
    }

    // MARK: Talk and listening

    private var talkRow: some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            HStack(spacing: Theme.space16) {
                Text("Talk").font(Theme.body).foregroundStyle(Theme.ink)
                SegmentedPicker(options: [(value: true, title: "Talk"), (value: false, title: "Quiet")], selection: Binding(
                    get: { session.voiceOn },
                    set: { on in
                        session.noteTouch()
                        session.voiceOn = on
                    }
                ))
            }
            Text("Talk reads steps and offers aloud; Quiet only shows them.")
                .font(Theme.caption).foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.space16)
        .padding(.vertical, Theme.space12)
        .frame(minHeight: 60)
    }

    private var listeningRow: some View {
        ToggleRow(label: "Listening", detail: "Off pauses it for 2 minutes", isOn: Binding(
            get: { session.listeningOn },
            set: { on in
                session.noteTouch()
                // A pause lasts 2 minutes, like "stop listening"; turning it on ends it.
                if on { session.toggleListening() } else { session.pauseListening() }
            }
        ))
    }

    // MARK: Voice

    /// The name of the voice that speaks now: the one chosen, or the best on the phone.
    private var voiceName: String {
        if let id = session.voiceID, let option = session.voiceOptions.first(where: { $0.id == id }) {
            return option.name
        }
        return Speaker.voice(for: session.voiceID)?.name ?? "System"
    }

    private var speedRow: some View {
        HStack(spacing: Theme.space16) {
            Text("Voice speed").font(Theme.body).foregroundStyle(Theme.ink)
            SegmentedPicker(options: VoiceSpeed.allCases.map { (value: $0, title: $0.title) }, selection: Binding(
                get: { session.voiceSpeed },
                set: { speed in
                    session.noteTouch()
                    session.setVoiceSpeed(speed)
                }
            ))
        }
        .padding(.horizontal, Theme.space16)
        .frame(minHeight: 60)
    }

    // MARK: Details

    /// The details panel (with the practice recorder and the AI check) beside the cook screen.
    private var detailsRow: some View {
        let shown = session.showDebug
        return Row(label: "Details", value: shown ? "Shown" : "Hidden", action: {
            session.noteTouch()
            session.showDebug = !shown
            if !shown { session.open(.cook) }
        })
        .accessibilityHint(shown ? "Hides the details" : "Shows the details beside the cook screen")
    }
}

/// A row with a label, an optional caption, and a switch.
private struct ToggleRow: View {
    let label: String
    let detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.body).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.slate)
                }
            }
        }
        .tint(Theme.beet)
        .padding(.horizontal, Theme.space16)
        .padding(.vertical, Theme.space8)
        .frame(minHeight: 60)
    }
}

/// The app's version and the voice models' and libraries' notices.
private struct AboutSheet: View {
    let close: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space16) {
                ScreenTitle(text: "About") {
                    RoundIconButton(systemImage: "xmark", label: "Close", size: .small, style: .quiet, action: close)
                }
                GroupedRows {
                    Row(label: "Sous Vision", value: version)
                }
                Text("Credits")
                    .font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                    .padding(.top, Theme.space8)
                    .accessibilityAddTraits(.isHeader)
                GroupedRows {
                    ForEach(Credits.notices) { notice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.title).font(Theme.body).foregroundStyle(Theme.ink)
                            Text(notice.text)
                                .font(Theme.caption).foregroundStyle(Theme.slate)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(Theme.space16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.space24)
            .screenColumn()
        }
        .background(Theme.ground.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }
}

#Preview {
    ProfileScreen(session: CookSession())
        .background(Theme.ground)
}
