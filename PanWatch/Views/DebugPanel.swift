import SwiftUI

/// What the detector sees and decides, with live tuning. Useful for dialing in a new
/// kitchen, and for showing judges how a decision is made.
struct DebugPanel: View {
    @Bindable var session: CookSession
    @State private var recordingPractice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                liveSection
                voiceSection
                decisionSection
                AIChecksSection(checks: session.aiChecks) // AI confirm
                practiceSection
                statsSection
                tuningSection
                historySection
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.82))
    }

    private var liveSection: some View {
        let live = session.live
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Live")
            MetricRow(name: "State", value: PhaseStyle.label(for: live.phase))
            MetricRow(name: "Hand over pan", value: live.handInZone ? "Yes" : "No")
            MetricRow(name: "Hands seen", value: "\(live.hands.count)")
            MetricRow(name: "Hands counted", value: "\(live.handsCounted)")
            MetricRow(name: "Ignored as still", value: "\(live.handsIgnoredAsStill)")
            if live.learnedWithHand {
                Text("Learned the pan with a hand in view")
                    .font(.footnote)
                    .foregroundStyle(.yellow)
            }
            MetricRow(name: "Hand time", value: seconds(live.dwell))
            MetricRow(name: "Hand openness", value: live.handOpenness.map { String(format: "%.2f", $0) } ?? "-")
            MetricRow(name: "Hand opened", value: String(format: "%.2f", live.handOpened))
            MetricRow(name: "Motion", value: percent(live.motion))
            ChangeMeter(value: live.liveChange, threshold: session.settings.additionThreshold)
            MetricRow(name: "Analysis rate", value: String(format: "%.0f fps", live.analysisFPS))
            MetricRow(name: "Phone heat", value: heat(ProcessInfo.processInfo.thermalState))
        }
    }

    /// Whether listening can hear right now, and what became of the last thing it heard.
    private var voiceSection: some View {
        let voice = session.voiceReport
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Voice")
            MetricRow(name: "Status", value: voice.state.rawValue)
            MetricRow(name: "Recognition", value: voice.onDevice ? "On phone" : "Apple servers")
            MetricRow(name: "Heard", value: voice.heard.map { "\"\($0)\"" } ?? "-")
            MetricRow(name: "Result", value: voice.outcome ?? "-")
            MetricRow(name: "Model", value: voice.model ?? "-")
            MetricRow(name: "Restarts", value: "\(voice.restarts)")
            MetricRow(name: "Errors", value: "\(voice.errors)")
            if let error = voice.lastError {
                MetricRow(name: "Last error", value: error)
            }
        }
    }

    /// The Nov 4 gates for this cook: screen touches (three or fewer) and accepted offers.
    private var statsSection: some View {
        let stats = session.stats
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "This cook")
            MetricRow(name: "Screen touches", value: "\(stats.screenTouches)")
            MetricRow(name: "Voice commands", value: "\(stats.voiceCommands)")
            MetricRow(name: "Button presses", value: "\(stats.buttonPresses)")
            MetricRow(name: "Offers", value: "\(stats.offersMade) (\(stats.offersAccepted) yes, \(stats.offersDismissed) no)")
            MetricRow(name: "Accepted", value: stats.acceptanceRate.map { percent($0) } ?? "-")
        }
    }

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Last decision")
            if let why = session.live.noOffer {
                MetricRow(name: "Why no offer", value: why.text)
            }
            if let decision = session.decisions.first {
                MetricRow(name: "Verdict", value: verdict(decision.outcome))
                if decision.changeAlone {
                    MetricRow(name: "Caught by", value: "The change alone, no hand counted")
                }
                MetricRow(name: "Pan changed", value: "\(percent(decision.changedFraction)) of \(percent(decision.additionThreshold)) needed")
                MetricRow(name: "Brightness shift", value: String(format: "%+.0f", decision.medianLumaShift))
                MetricRow(name: "Hand time", value: seconds(decision.dwell))
                MetricRow(name: "Hand let go", value: decision.released ? "Yes" : String(format: "No (opened %.2f)", decision.handOpened))
                MetricRow(name: "Settled", value: decision.settledCleanly ? "Yes" : "Timed out")
                if let pictures = session.lastPictures {
                    HStack(alignment: .top, spacing: 6) {
                        if let before = pictures.before { Thumbnail(image: before, caption: "Before", width: 94) }
                        if let after = pictures.after { Thumbnail(image: after, caption: "After", width: 94) }
                        if let changes = pictures.changes { Thumbnail(image: changes, caption: "Changed", width: 94) }
                    }
                }
            } else {
                Text("Nothing judged yet. On a watched step, reach over the pan, drop something in, and pull your hand away.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// Records practice adds for tuning on a computer. Say "that was it" after each real add.
    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Practice recording")
            Toggle("Record practice", isOn: $recordingPractice)
                .onChange(of: recordingPractice) { _, on in session.setPracticeRecording(on) }
            Text("Records hand joints and a small picture of the pan box, 15 times a second. No video and no audio. Say \"that was it\" right after each real add.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let status = session.camera.analyzer.recorder.current
                VStack(alignment: .leading, spacing: 8) {
                    if status.file != nil {
                        MetricRow(name: "Recorded", value: String(format: "%.0f s, %.1f MB", status.seconds, Double(status.bytes) / 1_000_000))
                        MetricRow(name: "Marks", value: "\(status.markers)")
                    }
                    if let file = status.file, !status.isRecording {
                        ShareLink(item: file) {
                            Label("Share recording", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
            }
        }
        .font(.subheadline)
        .onAppear { recordingPractice = session.camera.analyzer.recorder.current.isRecording }
    }

    private var tuningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Tuning")
            TuningSlider(title: "Change needed", value: $session.settings.additionThreshold, range: 0.01...0.30, format: percent)
            TuningSlider(title: "Brightness step", value: $session.settings.lumaThreshold, range: 8...60) { String(format: "%.0f", $0) }
            TuningSlider(title: "Color step", value: $session.settings.chromaThreshold, range: 8...80) { String(format: "%.0f", $0) }
            TuningSlider(title: "Hand time needed", value: $session.settings.minimumDwell, range: 0.1...2.0, format: seconds)
            TuningSlider(title: "Longer is stirring", value: $session.settings.maximumDwell, range: 2...20, format: seconds)
            TuningSlider(title: "Hand opening needed", value: $session.settings.releaseThreshold, range: 0.1...1.0) { String(format: "%.2f", $0) }
            TuningSlider(title: "Hand zone margin", value: $session.settings.handZoneMargin, range: 0...0.6, format: percent)
            Toggle("Use the camera", isOn: Binding(get: { session.cameraOn }, set: { session.setCamera(on: $0) }))
            Toggle("Require a hand", isOn: $session.settings.requireHand)
            Toggle("Count a hand letting go", isOn: $session.settings.countRelease)
            Toggle("Count a change you can see", isOn: $session.settings.countVisibleChange)
            Toggle("Ignore lighting changes", isOn: $session.settings.lightingVeto)
            Toggle("Fast timers (seconds)", isOn: $session.fastTimers)
            Button("Reset tuning") { session.resetSettings() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .font(.subheadline)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Decisions")
            if session.decisions.isEmpty {
                Text("None yet.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(session.decisions) { decision in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(decision.outcome))
                        .frame(width: 8, height: 8)
                    Text(verdict(decision.outcome))
                    Spacer()
                    Text(percent(decision.changedFraction))
                        .monospacedDigit()
                    Text(seconds(decision.dwell))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.footnote)
            }
        }
    }

    private func verdict(_ outcome: DetectorDecision.Outcome) -> String {
        switch outcome {
        case .addition: "Addition"
        case .noChange: "No change"
        case .lightingChange: "Lighting change"
        case .stirring: "Stirring, ignored"
        }
    }

    private func color(_ outcome: DetectorDecision.Outcome) -> Color {
        switch outcome {
        case .addition: .green
        case .noChange: .gray
        case .lightingChange: .orange
        case .stirring: .gray
        }
    }

    private func heat(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Normal"
        case .fair: "Warm"
        case .serious: "Hot"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

private func percent(_ fraction: Double) -> String {
    fraction < 0.1 ? String(format: "%.1f%%", fraction * 100) : String(format: "%.0f%%", fraction * 100)
}

private func seconds(_ value: Double) -> String {
    String(format: "%.1f s", value)
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.6))
    }
}

private struct MetricRow: View {
    let name: String
    let value: String

    var body: some View {
        HStack {
            Text(name)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

/// How different the pan looks from its before-picture, against the addition threshold.
private struct ChangeMeter: View {
    let value: Double
    let threshold: Double

    var body: some View {
        let scale = max(0.3, threshold * 3)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Pan vs. before")
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(percent(value))
                    .monospacedDigit()
            }
            .font(.subheadline)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                    Capsule()
                        .fill(value >= threshold ? Color.green : Color.white.opacity(0.7))
                        .frame(width: proxy.size.width * min(1, value / scale))
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 2)
                        .offset(x: proxy.size.width * min(1, threshold / scale) - 1)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pan versus before")
        .accessibilityValue("\(percent(value)), threshold \(percent(threshold))")
    }
}

private struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(.green)
        }
    }
}
