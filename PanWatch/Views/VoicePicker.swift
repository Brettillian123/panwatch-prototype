import AVFoundation
import SwiftUI

/// The voice menu, from Settings or "change the voice": the phone's English voices under
/// plain words (Your voice, Best voices, Other voices), each with Hear it, and the one
/// speaking now marked Chosen. "Next voice" moves the highlight down a row and plays it,
/// so a cook can walk the list without touching anything; "use this one" picks it.
struct VoicePicker: View {
    let session: CookSession
    /// Nil while the phone is still asking the cook about their Personal Voice.
    @State private var personalStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus?

    var body: some View {
        MenuScreen(session: session, title: "Choose a voice") {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gap * 2) {
                        NaturalVoices(session: session, rows: { rows($0) })
                        SpeedControl(session: session)
                        group("Your voice") { personalRows }
                        let others = session.voiceOptions.filter { !$0.isPersonal && !$0.isNatural }
                        let best = others.filter { $0.quality == .premium || $0.quality == .enhanced }
                        let rest = others.filter { $0.quality != .premium && $0.quality != .enhanced }
                        if !best.isEmpty {
                            group("Best voices") { rows(best) }
                        }
                        if !rest.isEmpty {
                            group("Other voices") { rows(rest) }
                        }
                        if others.isEmpty {
                            group("Other voices") {
                                Text("None on this phone")
                                    .font(Theme.control)
                                    .foregroundStyle(Theme.ash)
                                    .frame(minHeight: Theme.bigTarget)
                            }
                        }
                    }
                }
                // "Next voice" may walk past the bottom of the screen; keep its row in view.
                .onChange(of: session.highlightedVoiceID) { _, id in
                    guard let id else { return }
                    withAnimation(Theme.motion) { scroller.scrollTo(id, anchor: .center) }
                }
            }
        }
        .task {
            personalStatus = await Speaker.requestPersonalVoice()
            // A Personal Voice only appears once the cook has allowed it.
            session.refreshVoices()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            session.refreshVoices()
        }
    }

    /// The voice speaking now: the one picked, or the best installed when none is.
    private var chosenID: String? {
        session.voiceID ?? Speaker.best?.identifier
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: @escaping () -> Rows) -> some View {
        VoiceGroup(title: title, rows: rows)
    }

    @ViewBuilder private var personalRows: some View {
        let mine = session.voiceOptions.filter(\.isPersonal)
        if !mine.isEmpty {
            rows(mine)
        } else {
            HStack(spacing: Theme.gap) {
                Text(personalNote)
                    .font(Theme.control)
                    .foregroundStyle(Theme.ash)
                Spacer(minLength: Theme.gap)
                if personalStatus == .notDetermined {
                    Button("Use my voice") {
                        session.noteTouch()
                        Task {
                            personalStatus = await Speaker.requestPersonalVoice()
                            session.refreshVoices()
                        }
                    }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                } else if personalStatus == .denied {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                }
            }
            .frame(minHeight: Theme.bigTarget)
        }
    }

    /// Every state of the cook's own voice, drawn: asking, none made, not allowed, no support.
    private var personalNote: String {
        switch personalStatus {
        case nil: "Asking for your voice"
        case .authorized?: "None on this phone"
        case .denied?: "Not allowed"
        case .unsupported?: "Not on this phone"
        default: "Not set up"
        }
    }

    private func rows(_ options: [VoiceOption]) -> AnyView {
        AnyView(rowList(options))
    }

    @ViewBuilder private func rowList(_ options: [VoiceOption]) -> some View {
        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
            if index > 0 { RowRule() }
            VoiceRow(
                option: option,
                chosen: chosenID == option.id,
                highlighted: session.highlightedVoiceID == option.id,
                playing: session.sampleVoiceID == option.id,
                use: {
                    session.noteTouch()
                    session.useVoice(option)
                },
                hear: {
                    session.noteTouch()
                    session.highlightVoice(option.id)
                    if session.sampleVoiceID == option.id {
                        session.stopSample()
                    } else {
                        session.playSample(voiceID: option.id)
                    }
                }
            )
            .id(option.id)
        }
    }
}

/// One voice: its name and accent, Chosen or a Use button, and Hear it. The row "next
/// voice" stopped on is lifted with the rule color.
private struct VoiceRow: View {
    let option: VoiceOption
    let chosen: Bool
    let highlighted: Bool
    let playing: Bool
    let use: () -> Void
    let hear: () -> Void

    var body: some View {
        HStack(spacing: Theme.gap) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.tight) {
                Text(option.name)
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
                Text(option.isNatural ? option.detail : option.region)
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.gap)
            if chosen {
                Text("Chosen")
                    .font(Theme.control)
                    .foregroundStyle(Theme.copper)
                    .frame(minWidth: 120)
            } else {
                Button(action: use) {
                    Text("Use").frame(minWidth: 84)
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
                .accessibilityLabel("Use \(option.name)")
            }
            Button(action: hear) {
                Text(playing ? "Stop" : "Hear it").frame(minWidth: 96)
            }
            .buttonStyle(WordButtonStyle(height: Theme.target))
            .accessibilityLabel(playing ? "Stop \(option.name)" : "Hear \(option.name)")
        }
        .padding(.horizontal, Theme.tight)
        .frame(minHeight: Theme.bigTarget)
        .background(
            highlighted ? Theme.rule : Color.clear,
            in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
