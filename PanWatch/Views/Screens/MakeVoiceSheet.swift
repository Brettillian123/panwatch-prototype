import SwiftUI

/// The make-a-voice sheet: record your own voice, or blend two. Opened from Profile's
/// "Custom voice"; `RootView` draws it over the screen it was opened from while the screen
/// is `.makeVoice`, and closing goes back there. Recording comes first, the simpler path.
struct MakeVoiceSheet: View {
    let session: CookSession
    @State private var mode: Mode = .record

    enum Mode: Hashable { case blend, record }

    var body: some View {
        BottomSheet(title: "Make a voice", close: {
            session.noteTouch()
            session.closeMenu()
        }) {
            SegmentedPicker(options: [(value: Mode.record, title: "Use my own voice"), (value: Mode.blend, title: "Mix two voices")],
                            selection: $mode)
            switch mode {
            case .blend: BlendTwo(session: session)
            case .record: RecordMine(session: session)
            }
        }
    }
}

/// The scrolling middle of the sheet and its one main action pinned below it, so the
/// action stays in the thumb zone and a landscape phone can still reach everything.
private struct SheetBody<Content: View, Action: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: Theme.space16) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space16) { content }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(maxHeight: 480)
            action
        }
    }
}

// MARK: - Blend two

/// Two natural voices and a balance between them, heard, named and saved.
private struct BlendTwo: View {
    let session: CookSession
    @State private var first = "af_bella"
    @State private var second = "bm_george"
    @State private var balance = 0.5
    @State private var name = ""
    @State private var busy = false
    @State private var problem: String?

    /// The natural voices are on the phone. A `-uiScreen makeVoice` screenshot shows the
    /// controls without the download, which the simulator cannot do.
    private var ready: Bool {
        #if DEBUG
        if ScreenshotStage.requested == "makeVoice" { return true }
        #endif
        return session.naturalState == .ready
    }

    var body: some View {
        if !ready {
            SheetBody {
                Text("To mix voices, get more voices first.")
                    .font(Theme.body).foregroundStyle(Theme.slate)
                NaturalVoicesDownload(session: session)
            } action: {
                EmptyView()
            }
        } else {
            SheetBody {
                tiles
                Card {
                    VStack(alignment: .leading, spacing: Theme.space8) {
                        Text("Mix").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                        AppSlider(label: "Mix", value: share, fills: false,
                                  lowLabel: shortName(first), highLabel: shortName(second))
                            .accessibilityValue("\(Int((balance * 100).rounded())) percent \(shortName(first))")
                    }
                }
                Card {
                    SpeedSlider(session: session)
                }
                TextField("Name this voice", text: $name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, Theme.space16)
                    .frame(minHeight: 48)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                    .accessibilityLabel("Name")
                QuietButton(title: "Listen", systemImage: "play.fill") { run(save: false) }
                    .disabled(busy || first == second)
                if let note {
                    Text(note).font(Theme.caption).foregroundStyle(Theme.slate)
                }
                removeMix
            } action: {
                PrimaryButton(title: busy ? "Saving" : "Save voice") { run(save: true) }
                    .disabled(busy || first == second)
            }
        }
    }

    /// Left of the slider is all of the first voice; `balance` is how much of the first.
    private var share: Binding<Double> {
        Binding(get: { 1 - balance }, set: { balance = 1 - ($0 * 10).rounded() / 10 })
    }

    private var note: String? {
        if first == second { return "Pick two different voices." }
        return problem
    }

    private var tiles: some View {
        HStack(spacing: Theme.space8) {
            tile(selection: $first, fill: Theme.blush, which: "First")
            tile(selection: $second, fill: Theme.sky, which: "Second")
        }
        .overlay {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: Circle())
                .controlShadow()
                .accessibilityHidden(true)
        }
    }

    /// A voice tile: its play button and its name; tapping the name picks another voice.
    private func tile(selection: Binding<String>, fill: Color, which: String) -> some View {
        HStack(spacing: Theme.space8) {
            RoundIconButton(systemImage: "play.fill", label: "Listen to \(shortName(selection.wrappedValue))") {
                session.noteTouch()
                session.playSample(voiceID: VoiceCatalog.idPrefix + selection.wrappedValue)
            }
            Menu {
                Picker("\(which) voice", selection: selection) {
                    ForEach(VoiceCatalog.voices) { voice in
                        Text("\(voice.name), \(voice.accent.title)").tag(voice.pack)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(shortName(selection.wrappedValue))
                        .font(Theme.bodyStrong).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.slate)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(which) voice, \(shortName(selection.wrappedValue))")
        }
        .padding(.horizontal, Theme.space12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
    }

    /// The cook's saved mixes, any of which can be removed.
    @ViewBuilder private var removeMix: some View {
        let fixed = Set(VoiceCatalog.voices.map(\.id))
        let own = session.voiceOptions.filter {
            $0.isNatural && !fixed.contains($0.id) && $0.id != VoiceCatalog.bellaAndSarah.voice.id
        }
        if !own.isEmpty {
            Menu {
                ForEach(own) { option in
                    Button(option.name, role: .destructive) {
                        session.noteTouch()
                        session.removeBlend(option)
                    }
                }
            } label: {
                Text("Remove a mix")
                    .font(Theme.bodyStrong)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.fill, in: Capsule(style: .continuous))
            }
            .accessibilityLabel("Remove a mix")
        }
    }

    private func shortName(_ pack: String) -> String {
        VoiceCatalog.voice(pack: pack)?.name ?? pack
    }

    private func run(save: Bool) {
        session.noteTouch()
        busy = true
        problem = nil
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = typed.isEmpty ? "\(shortName(first)) and \(shortName(second))" : typed
        Task {
            do {
                if save {
                    try await session.saveBlend(name: name, first: first, second: second, balance: balance)
                    self.name = ""
                    session.closeMenu()
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

/// Slower, normal or faster, for every voice; each change says a line at the new speed.
struct SpeedSlider: View {
    let session: CookSession

    var body: some View {
        HStack(spacing: Theme.space16) {
            Text("Speed").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
            AppSlider(label: "Speed", value: index, range: 0...Double(VoiceSpeed.allCases.count - 1))
                .accessibilityValue(session.voiceSpeed.title)
            Text(session.voiceSpeed.title)
                .font(Theme.body).foregroundStyle(Theme.slate)
                .frame(minWidth: 64, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var index: Binding<Double> {
        Binding(
            get: { Double(VoiceSpeed.allCases.firstIndex(of: session.voiceSpeed) ?? 1) },
            set: { value in
                let all = VoiceSpeed.allCases
                let speed = all[max(0, min(all.count - 1, Int(value.rounded())))]
                guard speed != session.voiceSpeed else { return }
                session.noteTouch()
                session.setVoiceSpeed(speed)
            }
        )
    }
}

// MARK: - Record mine

/// The cook's own voice: the recording flow when there is none, otherwise the voice with
/// its model's state, a sample, rename and delete.
private struct RecordMine: View {
    let session: CookSession

    var body: some View {
        if let saved = session.ownVoice.saved {
            OwnVoiceManage(session: session, saved: saved)
        } else {
            OwnVoiceRecording(session: session)
        }
    }
}

private struct OwnVoiceManage: View {
    let session: CookSession
    let saved: SavedOwnVoice
    @State private var renaming = false
    @State private var deleting = false
    @State private var newName = ""

    var body: some View {
        let ready = session.ownVoice.isReady
        let playing = session.sampleVoiceID == OwnVoice.id
        let chosen = session.voiceID == OwnVoice.id
        SheetBody {
            Card {
                VStack(alignment: .leading, spacing: Theme.space12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(saved.name).font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                        Text(chosen ? "Recorded by you · In use" : "Recorded by you")
                            .font(Theme.caption).foregroundStyle(Theme.slate)
                    }
                    status
                }
            }
            QuietButton(title: playing ? "Stop" : "Listen", systemImage: playing ? "stop.fill" : "play.fill") {
                session.noteTouch()
                if playing { session.stopSample() } else { session.playSample(voiceID: OwnVoice.id) }
            }
            .disabled(!ready && !playing)
            QuietButton(title: "Rename", systemImage: "pencil") {
                session.noteTouch()
                newName = saved.name
                renaming = true
            }
            QuietButton(title: "Delete my voice", systemImage: "trash") {
                session.noteTouch()
                deleting = true
            }
            Text("Your recording and your voice stay on this phone.")
                .font(Theme.caption).foregroundStyle(Theme.slate)
        } action: {
            if !chosen {
                PrimaryButton(title: "Use my voice") {
                    session.noteTouch()
                    if let option = session.voiceOptions.first(where: \.isOwn) { session.useVoice(option) }
                }
                .disabled(!ready)
            }
        }
        .alert("Rename your voice", isPresented: $renaming) {
            TextField("Name", text: $newName)
                .textInputAutocapitalization(.words)
            Button("Save") { session.renameOwnVoice(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your voice?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { session.deleteOwnVoice() }
        } message: {
            Text("The recording and the voice made from it are removed from this phone.")
        }
    }

    /// Every state of the model and the voice: not downloaded, downloading, being made, failed.
    @ViewBuilder private var status: some View {
        switch session.ownVoice.state {
        case .idle:
            Text("The first time takes a few minutes and uses Wi-Fi.")
                .font(Theme.body).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            QuietButton(title: "Get started", systemImage: "arrow.down.to.line") {
                session.noteTouch()
                session.prepareOwnVoice()
            }
        case .downloading(let share):
            VoiceProgressBar(share: share)
            Text(share < 0.99 ? "Getting ready, \(Int(share * 100))%" : "Getting your voice ready")
                .font(Theme.caption).foregroundStyle(Theme.slate).monospacedDigit()
        case .making:
            HStack(spacing: Theme.space8) {
                ProgressView().tint(Theme.beet)
                Text("Making your voice").font(Theme.caption).foregroundStyle(Theme.slate)
            }
        case .failed:
            Text("Connect to Wi-Fi and try again.").font(Theme.body).foregroundStyle(Theme.ink)
            QuietButton(title: "Try again", systemImage: "arrow.clockwise") {
                session.noteTouch()
                session.prepareOwnVoice()
            }
        case .ready:
            EmptyView()
        }
    }
}

/// Record your voice: the consent statement first and nothing recorded before it, then the
/// script with a level meter and a countdown, listen back, try again and save. Listening
/// pauses while this is open so the passage isn't taken as commands.
private struct OwnVoiceRecording: View {
    let session: CookSession
    @State private var flow = OwnVoiceFlow()
    @State private var recorder: VoiceRecorder?
    @State private var take = 0
    @State private var micDenied = false
    @State private var problem: String?

    var body: some View {
        Group {
            if flow.step == .consent {
                consent
            } else {
                recordingSteps
            }
        }
        .onAppear {
            if recorder == nil { recorder = session.makeVoiceRecorder() }
            session.stopSample()
            session.holdListeningForRecording(true)
        }
        .onDisappear {
            recorder?.discard()
            session.holdListeningForRecording(false)
        }
    }

    private var consent: some View {
        SheetBody {
            Text(OwnVoice.consentLine)
                .font(Theme.bodyStrong).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("You'll read a few lines aloud, about 15 seconds. Your voice never leaves this phone.")
                .font(Theme.body).foregroundStyle(Theme.slate)
                .fixedSize(horizontal: false, vertical: true)
        } action: {
            PrimaryButton(title: "This is my own voice") {
                session.noteTouch()
                flow.acceptConsent()
            }
        }
    }

    @ViewBuilder private var recordingSteps: some View {
        let recorder = recorder
        SheetBody {
            Card {
                Text(OwnVoice.script)
                    .font(Theme.body)
                    .foregroundStyle(flow.step == .recording ? Theme.ink : Theme.slate)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.space8) {
                VoiceProgressBar(share: flow.step == .recording ? (recorder?.level ?? 0) : 0)
                    .accessibilityLabel("Level")
                Text(meterLine(recorder))
                    .font(Theme.caption).foregroundStyle(Theme.slate).monospacedDigit()
            }
            if let problem {
                Text(problem).font(Theme.body).foregroundStyle(Theme.ink)
            }
            if micDenied {
                QuietButton(title: "Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            if flow.step == .recorded {
                QuietButton(title: recorder?.isPlaying == true ? "Stop" : "Listen",
                            systemImage: recorder?.isPlaying == true ? "stop.fill" : "play.fill") {
                    session.noteTouch()
                    if recorder?.isPlaying == true { recorder?.stopListening() } else { recorder?.listen() }
                }
                QuietButton(title: "Try again", systemImage: "arrow.counterclockwise") {
                    session.noteTouch()
                    recorder?.discard()
                    flow.tryAgain()
                }
            }
            Text("Everything stays on this phone.")
                .font(Theme.caption).foregroundStyle(Theme.slate)
        } action: {
            switch flow.step {
            case .recording:
                PrimaryButton(title: "Stop", systemImage: "stop.fill") { stop() }
            case .recorded:
                PrimaryButton(title: "Save voice") { keep() }
            default:
                PrimaryButton(title: "Record", systemImage: "mic.fill") { start() }
            }
        }
    }

    /// While recording, the seconds left before it stops by itself.
    private func meterLine(_ recorder: VoiceRecorder?) -> String {
        let seconds = recorder?.seconds ?? 0
        switch flow.step {
        case .recording: return "\(max(0, Int((OwnVoice.maxSeconds - seconds).rounded(.up)))) s left"
        case .recorded: return "\(Int(seconds)) s recorded"
        default: return "Tap Record, then read the passage"
        }
    }

    private func start() {
        session.noteTouch()
        problem = nil
        Task {
            guard await VoiceRecorder.requestMicrophone() else {
                micDenied = true
                problem = "Allow the microphone in Settings."
                return
            }
            micDenied = false
            guard let recorder, let number = flow.startRecording() else { return }
            take = number
            let started = recorder.start(stopped: { finishTake(seconds: recorder.seconds) })
            if !started {
                flow.stopRecording(take: number, seconds: 0)
                problem = "The microphone couldn't start. Try again."
            }
        }
    }

    private func stop() {
        session.noteTouch()
        guard let recorder else { return }
        finishTake(seconds: recorder.stop())
    }

    private func finishTake(seconds: Double) {
        flow.stopRecording(take: take, seconds: seconds)
        if flow.problem == .tooShort {
            recorder?.discard()
            problem = "That was short. Read all the lines."
        }
    }

    private func keep() {
        session.noteTouch()
        guard let recorder, flow.finish(take: take) else { return }
        recorder.stopListening()
        do {
            try session.keepOwnVoice(samples: recorder.samples, name: OwnVoice.defaultName)
        } catch {
            problem = error.localizedDescription
        }
    }
}

#Preview {
    MakeVoiceSheet(session: CookSession())
}
