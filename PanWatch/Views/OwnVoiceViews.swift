import SwiftUI

/// The cook's recorded voice in the voice menu's "Your voice" group: Record your voice
/// when there's none, otherwise its row with Hear it, Use, Rename and Delete, and the
/// model download while it runs.
struct OwnVoiceRows: View {
    let session: CookSession
    let chosenID: String?
    @State private var recording = false
    @State private var renaming = false
    @State private var deleting = false
    @State private var newName = ""

    var body: some View {
        let own = session.ownVoice
        Group {
            if let saved = own.saved {
                voiceRow(saved)
                status
            } else {
                HStack(spacing: Theme.gap) {
                    Text("Speak in your own voice")
                        .font(Theme.control)
                        .foregroundStyle(Theme.ash)
                    Spacer(minLength: Theme.gap)
                    Button("Record your voice") {
                        session.noteTouch()
                        recording = true
                    }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                }
                .frame(minHeight: Theme.bigTarget)
            }
        }
        .sheet(isPresented: $recording) {
            OwnVoiceRecording(session: session, done: { recording = false })
                .interactiveDismissDisabled()
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

    private func voiceRow(_ saved: SavedOwnVoice) -> some View {
        let ready = session.ownVoice.isReady
        let playing = session.sampleVoiceID == OwnVoice.id
        let chosen = chosenID == OwnVoice.id
        return VStack(alignment: .leading, spacing: Theme.tight) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.tight) {
                Text(saved.name)
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
                Text("Recorded by you")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                    .lineLimit(1)
                Spacer(minLength: Theme.gap)
                if chosen {
                    Text("Chosen")
                        .font(Theme.control)
                        .foregroundStyle(Theme.copper)
                }
            }
            HStack(spacing: Theme.tight) {
                Button(playing ? "Stop" : "Hear it") {
                    session.noteTouch()
                    if playing {
                        session.stopSample()
                    } else {
                        session.playSample(voiceID: OwnVoice.id)
                    }
                }
                .disabled(!ready && !playing)
                .accessibilityLabel(playing ? "Stop \(saved.name)" : "Hear \(saved.name)")
                if !chosen {
                    Button("Use") {
                        session.noteTouch()
                        if let option = session.voiceOptions.first(where: \.isOwn) { session.useVoice(option) }
                    }
                    .accessibilityLabel("Use \(saved.name)")
                }
                Button("Rename") {
                    session.noteTouch()
                    newName = saved.name
                    renaming = true
                }
                Button("Delete") {
                    session.noteTouch()
                    deleting = true
                }
            }
            .buttonStyle(WordButtonStyle(height: Theme.target))
        }
        .padding(.horizontal, Theme.tight)
        .frame(minHeight: Theme.bigTarget)
        .id(OwnVoice.id)
    }

    /// Every state of the model and the voice: not downloaded, downloading, being made,
    /// failed. Nothing once ready.
    @ViewBuilder private var status: some View {
        switch session.ownVoice.state {
        case .idle:
            HStack(spacing: Theme.gap) {
                Text("One download, about 500 MB")
                    .font(Theme.control)
                    .foregroundStyle(Theme.ash)
                Spacer(minLength: Theme.gap)
                Button("Download") {
                    session.noteTouch()
                    session.prepareOwnVoice()
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
            }
            .frame(minHeight: Theme.bigTarget)
        case .downloading(let share):
            VStack(alignment: .leading, spacing: Theme.tight) {
                ProgressView(value: share)
                    .tint(Theme.copper)
                Text(share < 0.99 ? "Downloading, \(Int(share * 100))%" : "Getting your voice ready")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
                    .monospacedDigit()
            }
            .frame(minHeight: Theme.bigTarget)
        case .making:
            HStack(spacing: Theme.gap) {
                ProgressView()
                Text("Making your voice")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.ash)
            }
            .frame(minHeight: Theme.bigTarget)
        case .failed:
            HStack(spacing: Theme.gap) {
                Text("Your voice isn't ready")
                    .font(Theme.control)
                    .foregroundStyle(Theme.ash)
                Spacer(minLength: Theme.gap)
                Button("Try again") {
                    session.noteTouch()
                    session.prepareOwnVoice()
                }
                .buttonStyle(WordButtonStyle(height: Theme.target))
            }
            .frame(minHeight: Theme.bigTarget)
        case .ready:
            EmptyView()
        }
    }
}

/// Record your voice: the consent line first, then the script in large type with a level
/// meter, Record, Stop, Listen back, Try again and Keep. Live from the microphone only.
private struct OwnVoiceRecording: View {
    let session: CookSession
    let done: () -> Void
    @State private var flow = OwnVoiceFlow()
    @State private var recorder: VoiceRecorder?
    @State private var take = 0
    @State private var micDenied = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap * 1.5) {
            HStack {
                Text("Record your voice")
                    .font(Theme.step)
                    .foregroundStyle(Theme.flour)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancel") { close() }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
            }
            if flow.step == .consent {
                consent
            } else {
                recordingSteps
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.gap * 1.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.iron)
        .preferredColorScheme(.dark)
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
        VStack(alignment: .leading, spacing: Theme.gap * 1.5) {
            Text(OwnVoice.consentLine)
                .font(Theme.step)
                .foregroundStyle(Theme.flour)
                .fixedSize(horizontal: false, vertical: true)
            Text("You'll read a short passage aloud for about 15 seconds. Your voice is made on this phone and never uploaded.")
                .font(Theme.reading)
                .foregroundStyle(Theme.ash)
                .fixedSize(horizontal: false, vertical: true)
            Button("This is my own voice") {
                session.noteTouch()
                flow.acceptConsent()
            }
            .buttonStyle(WordButtonStyle(height: Theme.bigTarget))
        }
    }

    @ViewBuilder private var recordingSteps: some View {
        let recorder = recorder
        Text(OwnVoice.script)
            .font(Theme.step)
            .foregroundStyle(flow.step == .recording ? Theme.flour : Theme.ash)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: Theme.tight) {
            ProgressView(value: recorder?.level ?? 0)
                .tint(Theme.herb)
                .accessibilityLabel("Level")
            Text(meterLine(recorder))
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
                .monospacedDigit()
        }
        if let problem {
            Text(problem)
                .font(Theme.reading)
                .foregroundStyle(Theme.ash)
        }
        if micDenied {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(WordButtonStyle(height: Theme.bigTarget))
        }
        HStack(spacing: Theme.gap) {
            switch flow.step {
            case .recording:
                Button("Stop") { stop() }
            case .recorded:
                Button(recorder?.isPlaying == true ? "Stop" : "Listen back") {
                    session.noteTouch()
                    if recorder?.isPlaying == true { recorder?.stopListening() } else { recorder?.listen() }
                }
                Button("Try again") {
                    session.noteTouch()
                    recorder?.discard()
                    flow.tryAgain()
                }
                Button("Keep") { keep() }
            default:
                Button("Record") { start() }
            }
        }
        .buttonStyle(WordButtonStyle(height: Theme.bigTarget))
    }

    private func meterLine(_ recorder: VoiceRecorder?) -> String {
        let seconds = Int(recorder?.seconds ?? 0)
        switch flow.step {
        case .recording: return "Recording, \(seconds) s"
        case .recorded: return "\(seconds) s recorded"
        default: return "Tap Record, then read the passage"
        }
    }

    private func start() {
        session.noteTouch()
        problem = nil
        Task {
            guard await VoiceRecorder.requestMicrophone() else {
                micDenied = true
                problem = "The microphone isn't allowed."
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
            problem = "That was short. Read the whole passage."
        }
    }

    private func keep() {
        session.noteTouch()
        guard let recorder, flow.finish(take: take) else { return }
        recorder.stopListening()
        do {
            try session.keepOwnVoice(samples: recorder.samples, name: OwnVoice.defaultName)
            done()
        } catch {
            problem = error.localizedDescription
        }
    }

    private func close() {
        session.noteTouch()
        recorder?.discard()
        done()
    }
}
