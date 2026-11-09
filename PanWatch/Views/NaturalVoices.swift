import SwiftUI

/// A titled group of rows in the voice menu.
struct VoiceGroup<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text(title)
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                rows()
            }
        }
    }
}

/// The top of the voice menu: the Kokoro voices by accent, the cook's mixes, the
/// download while it runs, and Make your own once the voices are on the phone.
struct NaturalVoices: View {
    let session: CookSession
    let rows: ([VoiceOption]) -> AnyView

    var body: some View {
        let natural = session.voiceOptions.filter(\.isNatural)
        let fixed = Set(VoiceCatalog.voices.map(\.id))
        VoiceGroup(title: "Natural voices") {
            status
            ForEach(VoiceAccent.allCases, id: \.self) { accent in
                Subheading(text: accent.title)
                rows(natural.filter { fixed.contains($0.id) && $0.accent == accent })
            }
            let mixes = natural.filter { !fixed.contains($0.id) }
            if !mixes.isEmpty {
                Subheading(text: "Mixes")
                rows(mixes)
                let own = mixes.filter { $0.id != VoiceCatalog.bellaAndSarah.voice.id }
                if !own.isEmpty {
                    Menu("Remove a mix") {
                        ForEach(own) { option in
                            Button(option.name, role: .destructive) {
                                session.noteTouch()
                                session.removeBlend(option)
                            }
                        }
                    }
                    .font(Theme.control)
                    .frame(minHeight: Theme.bigTarget)
                }
            }
            if session.naturalState == .ready {
                BlendMaker(session: session)
            }
        }
    }

    /// Every state of the download: not started, under way, failed. Nothing once ready.
    @ViewBuilder private var status: some View {
        switch session.naturalState {
        case .idle:
            HStack(spacing: Theme.gap) {
                Text("One download, about 230 MB")
                    .font(Theme.control)
                    .foregroundStyle(Theme.ash)
                Spacer(minLength: Theme.gap)
                Button("Download") {
                    session.noteTouch()
                    session.prepareNaturalVoices()
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
            }
            .frame(minHeight: Theme.bigTarget)
        case .downloading(let share):
            VStack(alignment: .leading, spacing: Theme.tight) {
                ProgressView(value: share)
                    .tint(Theme.copper)
                Text(share < 0.99 ? "Downloading, \(Int(share * 100))%" : "Getting the voices ready")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                    .monospacedDigit()
            }
            .frame(minHeight: Theme.bigTarget)
        case .failed:
            HStack(spacing: Theme.gap) {
                Text("Download stopped")
                    .font(Theme.control)
                    .foregroundStyle(Theme.ash)
                Spacer(minLength: Theme.gap)
                Button("Try again") {
                    session.noteTouch()
                    session.prepareNaturalVoices()
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
            }
            .frame(minHeight: Theme.bigTarget)
        case .ready:
            EmptyView()
        }
    }
}

private struct Subheading: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.detail.weight(.semibold))
            .foregroundStyle(Theme.flour)
            .padding(.top, Theme.tight)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Slower, normal or faster, for every voice.
struct SpeedControl: View {
    let session: CookSession

    var body: some View {
        VoiceGroup(title: "Speed") {
            Picker("Speed", selection: Binding(
                get: { session.voiceSpeed },
                set: { speed in
                    session.noteTouch()
                    session.setVoiceSpeed(speed)
                }
            )) {
                ForEach(VoiceSpeed.allCases, id: \.self) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: Theme.bigTarget)
        }
    }
}

/// Make your own: two voices and a balance between them, heard, named and saved.
private struct BlendMaker: View {
    let session: CookSession
    @State private var first = "af_bella"
    @State private var second = "bm_george"
    @State private var balance = 0.5
    @State private var name = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Subheading(text: "Make your own")
            HStack(spacing: Theme.gap) {
                voiceMenu(selection: $first)
                Text("and")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                voiceMenu(selection: $second)
            }
            HStack(spacing: Theme.tight) {
                Text(shortName(first))
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                Slider(value: $balance, in: 0...1, step: 0.1)
                    .tint(Theme.copper)
                    .accessibilityLabel("Balance")
                    .accessibilityValue("\(Int((1 - balance) * 100)) percent \(shortName(second))")
                Text(shortName(second))
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
            }
            .frame(minHeight: Theme.bigTarget)
            HStack(spacing: Theme.gap) {
                TextField("Name", text: $name)
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, Theme.tight)
                    .frame(minHeight: Theme.target)
                    .background(Theme.rule, in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
                Button("Hear it") { run(save: false) }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                    .disabled(busy || first == second)
                Button("Save") { run(save: true) }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                    .disabled(busy || first == second || trimmed.isEmpty)
            }
            if let problem {
                Text(problem)
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
            }
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func shortName(_ pack: String) -> String {
        VoiceCatalog.voice(pack: pack)?.name ?? pack
    }

    private func voiceMenu(selection: Binding<String>) -> some View {
        Picker("Voice", selection: selection) {
            ForEach(VoiceCatalog.voices) { voice in
                Text("\(voice.name), \(voice.accent.title)").tag(voice.pack)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.flour)
    }

    private func run(save: Bool) {
        session.noteTouch()
        busy = true
        problem = nil
        let name = trimmed
        Task {
            do {
                if save {
                    try await session.saveBlend(name: name, first: first, second: second, balance: balance)
                    self.name = ""
                } else {
                    try await session.hearBlend(first: first, second: second, balance: balance)
                }
            } catch {
                problem = error.localizedDescription
            }
            busy = false
        }
    }
}
