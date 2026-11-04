import AVFoundation
import SwiftUI

/// The voice menu: the cook's own Personal Voice, then every English voice on the phone by
/// quality, each with a sample to play. Big type, because the phone may already be propped
/// at the back of the stove.
struct VoicePicker: View {
    let session: CookSession
    @Environment(\.dismiss) private var dismiss
    /// Nil until the phone's voices have been read.
    @State private var voices: [VoiceOption]?
    /// Nil while the phone is still asking the cook.
    @State private var personalStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus?

    private static let qualities: [AVSpeechSynthesisVoiceQuality] = [.premium, .enhanced, .default]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VoiceRow(
                        name: "Best installed",
                        detail: Speaker.best.map { "Now \($0.name)" } ?? "System voice",
                        selected: session.voiceID == nil,
                        playing: Speaker.best.map { session.sampleVoiceID == $0.identifier } ?? false,
                        choose: { session.chooseVoice(nil) },
                        play: Speaker.best.map { best -> () -> Void in { toggleSample(best.identifier) } }
                    )
                }
                personalSection
                englishSections
                Section {
                    note("Get more voices: Settings > Accessibility > Read & Speak > Voices.")
                }
            }
            .navigationTitle("Voice")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.title3.weight(.semibold))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            voices = Speaker.options()
            personalStatus = await Speaker.requestPersonalVoice()
            // Personal Voices only appear in the list once allowed.
            voices = Speaker.options()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            voices = Speaker.options()
        }
        .onDisappear {
            if session.sampleVoiceID != nil { session.stopSample() }
        }
    }

    @ViewBuilder private var personalSection: some View {
        let mine = (voices ?? []).filter(\.isPersonal)
        Section("Personal Voice") {
            switch personalStatus {
            case nil:
                HStack(spacing: 12) {
                    ProgressView()
                    note("Asking to use your Personal Voice")
                }
            case .authorized?:
                if mine.isEmpty {
                    note("None on this phone yet. Make one in Settings > Accessibility > Personal Voice.")
                } else {
                    ForEach(mine) { row($0, detail: "Your voice") }
                }
            case .denied?:
                note("Not allowed. Turn on Sous Vision in Settings > Accessibility > Personal Voice.")
            case .unsupported?:
                note("This phone can't use Personal Voice.")
            default:
                Button("Use my Personal Voice") {
                    Task {
                        personalStatus = await Speaker.requestPersonalVoice()
                        voices = Speaker.options()
                    }
                }
                .font(.headline)
            }
        }
    }

    @ViewBuilder private var englishSections: some View {
        if let voices {
            let english = voices.filter { !$0.isPersonal }
            if english.isEmpty {
                Section("English voices") {
                    note("No English voices found on this phone.")
                }
            } else {
                ForEach(Self.qualities, id: \.rawValue) { quality in
                    let group = english.filter { $0.quality == quality }
                    if !group.isEmpty {
                        Section(Self.title(of: quality)) {
                            ForEach(group) { row($0, detail: $0.region) }
                        }
                    }
                }
            }
        }
    }

    private static func title(of quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
    }

    private func row(_ option: VoiceOption, detail: String) -> some View {
        VoiceRow(
            name: option.name,
            detail: detail,
            selected: session.voiceID == option.id,
            playing: session.sampleVoiceID == option.id,
            choose: { session.chooseVoice(option.id) },
            play: { toggleSample(option.id) }
        )
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func toggleSample(_ id: String) {
        if session.sampleVoiceID == id {
            session.stopSample()
        } else {
            session.playSample(voiceID: id)
        }
    }
}

/// One voice: tap the name to use it, or play a sample first.
private struct VoiceRow: View {
    let name: String
    let detail: String
    let selected: Bool
    let playing: Bool
    let choose: () -> Void
    let play: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: choose) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.green)
                        .opacity(selected ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.title2.weight(.semibold))
                        Text(detail)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            if let play {
                Button(action: play) {
                    Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.headline)
                        .frame(minWidth: 84)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(playing ? Color.orange : Color.accentColor)
            }
        }
        .padding(.vertical, 6)
    }
}
