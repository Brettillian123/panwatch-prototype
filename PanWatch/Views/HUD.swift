import SwiftUI

/// The current recipe step, big enough to read from across the stove.
struct StepCard: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(session.recipe.title.uppercased())  ·  STEP \(session.stepIndex + 1) OF \(session.recipe.steps.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
            Text(session.currentStep.instruction)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            WatchStatusChip(session: session)
        }
        .padding(18)
        .frame(maxWidth: 470, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Says whether the camera is watching this step, and what it's doing.
struct WatchStatusChip: View {
    let session: CookSession

    var body: some View {
        let status = self.status
        Label(status.text, systemImage: status.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status.color.opacity(0.18), in: Capsule())
    }

    private var status: (symbol: String, text: String, color: Color) {
        guard let watch = session.currentStep.watch else {
            return ("eye.slash", "Camera not needed for this step", .gray)
        }
        if session.isMarkingPan || session.region == nil {
            return ("viewfinder", "Mark the pan to start watching", .orange)
        }
        if session.suggestion != nil {
            return ("timer", "Waiting for your answer", .cyan)
        }
        if session.phase == .watching {
            return ("eye", "Watching for the \(watch.ingredient)", .green)
        }
        return (PhaseStyle.symbol(for: session.phase), PhaseStyle.label(for: session.phase), PhaseStyle.color(for: session.phase))
    }
}

/// Running and finished timers, top right.
struct TimerStack: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(session.timers) { timer in
                HStack(spacing: 10) {
                    Image(systemName: timer.isDone ? "bell.fill" : "timer")
                        .font(.title3)
                    Text(timer.label)
                        .font(.headline)
                    Group {
                        if timer.isDone {
                            Text("Done")
                        } else {
                            Text(timerInterval: timer.start...timer.end, countsDown: true)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    Button {
                        session.removeTimer(timer.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Remove \(timer.label) timer")
                }
                .foregroundStyle(.white)
                .padding(.leading, 16)
                .padding(.vertical, 2)
                .padding(.trailing, 2)
                .background(timer.isDone ? Color.red : Color.black.opacity(0.72), in: Capsule())
            }
        }
    }
}

/// Step navigation and setup controls along the bottom.
struct ControlBar: View {
    let session: CookSession

    var body: some View {
        HStack(spacing: 10) {
            Button { session.previousStep() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(session.stepIndex == 0)

            Button { session.nextStep() } label: {
                Label("Next step", systemImage: "chevron.right")
            }
            .disabled(session.isLastStep)

            Button { session.markPan() } label: {
                Label("Mark pan", systemImage: "viewfinder")
            }
            .disabled(session.isMarkingPan)

            Spacer(minLength: 8)

            Button { session.voiceOn.toggle() } label: {
                Image(systemName: session.voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .accessibilityLabel(session.voiceOn ? "Mute voice" : "Unmute voice")

            Button { Task { await session.flipCamera() } } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
            }
            .accessibilityLabel("Switch camera")

            Button { session.showDebug.toggle() } label: {
                Image(systemName: "waveform.path.ecg")
            }
            .accessibilityLabel(session.showDebug ? "Hide detection details" : "Show detection details")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .padding(10)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

/// Instructions while the cook draws the pan box.
struct MarkPanBanner: View {
    let session: CookSession

    var body: some View {
        VStack(spacing: 10) {
            Text(session.draftRegion == nil ? "Draw a box around the pan" : "Adjust the box, or start watching")
                .font(.title2.weight(.bold))
            Text(session.markingReason
                 ?? "Tap the pan for a quick box, or drag to draw one. Keep the phone still afterwards: exposure and white balance lock so lighting changes can't fool the camera.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                if session.region != nil {
                    Button("Cancel") { session.cancelMarking() }
                        .buttonStyle(.bordered)
                }
                Button { session.confirmPan() } label: {
                    Label("Start watching", systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.draftRegion == nil)
            }
            .controlSize(.large)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: 560)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Covers the screen when the camera can't run.
struct CameraStatusOverlay: View {
    let status: CameraStatus

    var body: some View {
        switch status {
        case .running:
            EmptyView()
        case .starting:
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        case .denied:
            message(
                symbol: "camera.fill",
                title: "PanWatch needs the camera to watch your pan",
                detail: "Video is analyzed on this phone and never saved or sent anywhere.",
                showsSettings: true
            )
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle.fill", title: "The camera couldn't start", detail: reason, showsSettings: false)
        }
    }

    private func message(symbol: String, title: String, detail: String, showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.largeTitle)
            Text(title)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            if showsSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 520)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
