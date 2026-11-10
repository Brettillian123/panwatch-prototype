import AVFoundation
import Speech
import SwiftUI

// MARK: - Phrases

/// The phrases that work on the cook screen right now, most useful first. The help sheet
/// shows them first; menus' Say line shows them too. Only commands the grammar understands.
enum CookPhrases {
    @MainActor static func now(_ session: CookSession) -> [String] {
        // A menu has its own few phrases.
        if session.screen != .cook && session.screen != .help { return session.sayPhrases }
        if session.suggestion != nil { return ["yes", "not now"] }
        if session.isMarkingPan {
            return session.draftRegion == nil ? ["cancel"] : ["start watching", "cancel"]
        }
        var list: [String] = []
        if session.needsPan {
            list += session.offeredPan != nil ? ["yes", "draw the pan again"] : ["mark the pan"]
        }
        if !session.isLastStep { list.append("next step") }
        if session.canStartStepTimer { list.append("start the timer") }
        if session.timers.contains(where: { !$0.isDone }) { list.append("how long") }
        if session.timers.contains(where: \.isDone) { list.append("clear it") }
        if session.stepIndex > 0 { list.append("back") }
        list += ["repeat", "ingredients"]
        if session.cameraOn && !session.needsPan { list.append("draw the pan again") }
        return list
    }

    /// Whether the microphone or speech recognition was refused.
    static var micDenied: Bool {
        let speech = SFSpeechRecognizer.authorizationStatus()
        return AVAudioApplication.shared.recordPermission == .denied || speech == .denied || speech == .restricted
    }
}

// MARK: - The chip

/// The one thing drawn over the camera picture: white, full round, 32 tall, an 18 glyph
/// and a caption. One state at a time. Tapping it turns listening off or on, or, with
/// the microphone refused, opens Settings.
struct CookChip: View {
    let session: CookSession
    var staged: String? = nil

    var body: some View {
        let state = self.state
        Button(action: tap) {
            HStack(spacing: 6) {
                Image(systemName: state.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(state.text)
                    .font(Theme.cookCaption)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.slate)
            .padding(.horizontal, Theme.space12)
            .frame(height: 32)
            .background(Theme.card, in: Capsule(style: .continuous))
            .controlShadow()
            .frame(minHeight: Theme.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.text)
        .accessibilityHint(micDenied ? "Opens Settings" : session.listeningOn ? "Stops listening" : "Starts listening")
        .animation(Theme.motion, value: state.text)
    }

    private var micDenied: Bool { session.listeningOn && !session.micReady && CookPhrases.micDenied }

    private var state: (symbol: String, text: String) {
        #if DEBUG
        if let staged { return staged == "cook" ? ("mic", "Listening") : ("eye", "Watching") }
        #endif
        if session.isSpeaking { return ("speaker.wave.2", "Speaking") }
        if let heard = session.heardText { return ("checkmark", "Heard \u{201C}\(heard)\u{201D}") }
        if session.needsPan { return ("viewfinder", "No pot marked") }
        if micDenied { return ("mic.slash", "Microphone off") }
        if session.listeningOn && session.micReady { return ("mic", "Listening") }
        if session.cameraOn && session.region != nil { return ("eye", "Watching") }
        return ("mic.slash", "Not listening")
    }

    private func tap() {
        session.noteTouch()
        if micDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        } else {
            session.toggleListening()
        }
    }
}

// MARK: - Timers

/// The timer in the card: a done one first, else the one ending soonest.
@MainActor func featuredTimer(_ timers: [CookTimer]) -> CookTimer? {
    timers.first(where: \.isDone) ?? timers.filter { !$0.isDone }.min { $0.end < $1.end }
}

/// The running timer, 72 tall: digits in the cook title size, its name, and a round clear
/// button (timers have no pause). With two or more, "+1 more" under the name, and a tap
/// opens the list. Done, the card turns blush with "Pasta timer is done" and Stop.
struct CookTimerCard: View {
    let session: CookSession
    let timer: CookTimer
    let openAll: () -> Void

    var body: some View {
        let others = session.timers.count - 1
        HStack(spacing: 14) {
            if timer.isDone {
                Text("\(timer.label) timer is done")
                    .font(Theme.cookBodyStrong)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if others > 0 { more(others) }
                Spacer(minLength: Theme.space8)
                Button {
                    session.noteTouch()
                    session.removeTimer(timer.id)
                } label: {
                    Text("Stop")
                        .font(Theme.cookBodyStrong)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 52)
                }
                .buttonStyle(KitPressStyle(fill: Theme.card, foreground: Theme.ink))
                .accessibilityLabel("Stop the \(timer.label.lowercased()) timer")
            } else {
                Text(timerInterval: timer.start...timer.end, pauseTime: timer.pausedAt, countsDown: true)
                    .font(Theme.cookTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(timer.label) timer")
                    if others > 0 { Text("+\(others) more") }
                }
                .font(Theme.cookCaption)
                .foregroundStyle(Theme.slate)
                .lineLimit(1)
                Spacer(minLength: Theme.space8)
                RoundIconButton(systemImage: "xmark", label: "Clear the \(timer.label.lowercased()) timer", size: .large, style: .quiet) {
                    session.noteTouch()
                    session.removeTimer(timer.id)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(timer.isDone ? Theme.blush : Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .cardShadow()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .onTapGesture { if others > 0 { openAll() } }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "All timers") { openAll() }
    }

    private func more(_ count: Int) -> some View {
        Text("+\(count) more")
            .font(Theme.cookCaption)
            .foregroundStyle(Theme.slate)
    }
}

/// Every timer with its control, opened from the timer card when two or more run. This
/// step's timer can be started here too.
struct TimersSheet: View {
    let session: CookSession
    let close: () -> Void

    var body: some View {
        BottomSheet(title: "Timers", close: close) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space16) {
                    if !session.timers.isEmpty {
                        GroupedRows {
                            ForEach(session.timers.sorted { $0.end < $1.end }) { timer in
                                Row(label: timer.isDone ? "\(timer.label) timer is done" : "\(timer.label) timer", leading: { EmptyView() }) {
                                    if !timer.isDone {
                                        Text(timerInterval: timer.start...timer.end, pauseTime: timer.pausedAt, countsDown: true)
                                            .font(Theme.body)
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.slate)
                                    }
                                    RoundIconButton(
                                        systemImage: "xmark",
                                        label: timer.isDone ? "Stop the \(timer.label.lowercased()) timer" : "Clear the \(timer.label.lowercased()) timer",
                                        style: .quiet
                                    ) {
                                        session.noteTouch()
                                        session.removeTimer(timer.id)
                                        if session.timers.isEmpty { close() }
                                    }
                                }
                            }
                        }
                    }
                    if session.canStartStepTimer, let watch = session.currentStep.watch {
                        QuietButton(title: "Start the \(watch.timerMinutes)-minute timer", systemImage: "timer") {
                            session.noteTouch()
                            session.startStepTimer()
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 220)
        }
    }
}

// MARK: - Say line (menus)

/// Along the bottom of the old menus: whether the app is listening, what it just heard, and
/// one phrase that works right now, changing every 4 s. Tapping it turns listening off or
/// on. Cook mode no longer shows it; its phrases are first in the help sheet.
struct SayLine: View {
    let session: CookSession

    var body: some View {
        Group {
            if session.listeningOn && !session.micReady && CookPhrases.micDenied {
                HStack(spacing: Theme.gap) {
                    Text("Microphone off")
                        .font(Theme.control)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(WordButtonStyle(height: Theme.target))
                }
                .padding(.trailing, Theme.tight)
            } else {
                Button {
                    session.noteTouch()
                    session.toggleListening()
                } label: {
                    HStack(spacing: Theme.gap) {
                        content
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(session.listeningOn ? "Stops listening" : "Starts listening")
            }
        }
        .padding(.leading, Theme.gap)
        .frame(maxWidth: .infinity, minHeight: Theme.bigTarget, maxHeight: Theme.bigTarget)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        if !session.listeningOn {
            line("Not listening, tap to listen", Theme.slate)
        } else if !session.micReady {
            line("Starting the microphone", Theme.slate)
        } else if let answer = session.answerText {
            line(answer, Theme.ink)
        } else if let heard = session.heardText {
            line("Heard \u{201C}\(heard)\u{201D}", Theme.ink)
        } else {
            let phrases = CookPhrases.now(session)
            TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 4)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 4) % max(phrases.count, 1)
                line(phrases.isEmpty ? "Listening" : "Say \u{201C}\(phrases[index])\u{201D}", Theme.ink)
            }
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.bodyStrong)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Camera status

/// Starting, denied and failed, as a small card at the bottom of the camera box: the box's
/// place is never just black.
struct CameraStatusOverlay: View {
    let status: CameraStatus

    var body: some View {
        switch status {
        case .running:
            EmptyView()
        case .starting:
            card {
                HStack(spacing: Theme.space8) {
                    ProgressView().tint(Theme.slate)
                    Text("Starting the camera").foregroundStyle(Theme.slate)
                }
            }
        case .denied:
            card {
                Text("Camera not allowed. Video is never saved or sent.").foregroundStyle(Theme.ink)
                QuietButton(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .failed(let reason):
            card {
                Text("The camera couldn\u{2019}t start").foregroundStyle(Theme.ink)
                Text(reason).foregroundStyle(Theme.slate).lineLimit(3)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) { content() }
            .font(Theme.cookCaption)
            .padding(Theme.space12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
