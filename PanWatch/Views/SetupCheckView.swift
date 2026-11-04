import SwiftUI

/// The setup check over the camera picture: what to do now in big words, a bar for the
/// seconds left, and a worded Skip button. Nothing shows when no check is running or
/// showing its result.
struct SetupCheckView: View {
    let check: SetupCheck

    var body: some View {
        switch check.stage {
        case .idle:
            EmptyView()
        case .still:
            card(title: "Keep your hands away", detail: "Checking the light for two seconds.", running: true)
        case .hand:
            card(title: "Now hold one hand over the pot", detail: "Checking that I can see your hand.", running: true)
        case .done(let result):
            if let fix = result.fix {
                card(title: fix.title, detail: fix.fix, running: false, tint: .orange)
            } else {
                card(title: "Ready", detail: "Detection is set for this kitchen.", running: false, tint: .green)
            }
        }
    }

    private func card(title: String, detail: String, running: Bool, tint: Color = .white) -> some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if running {
                TimelineView(.animation) { context in
                    ProgressView(value: check.progress(at: context.date))
                        .tint(.white)
                }
                Button { check.skip() } label: {
                    Text("Skip the check")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            } else {
                Button { check.dismiss() } label: {
                    Text("OK")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
        .padding(16)
        .transition(.opacity)
    }
}
