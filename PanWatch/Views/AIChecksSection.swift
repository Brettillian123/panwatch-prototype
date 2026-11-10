import SwiftUI

/// AI confirm: the debug panel's list of on-device checks: the frames sent, the answer,
/// how sure the model was, and how long it took.
struct AIChecksSection: View {
    let checks: [AICheckRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI CHECK")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            Text(AddModel.status)
                .font(.footnote)
            if checks.isEmpty {
                Text("No checks yet. On a watched step, the rules' guesses are sent here before any offer.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            ForEach(checks) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check \(check.id): \(check.answer)")
                        .font(.footnote.weight(.semibold))
                    Text(details(check))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(Array(check.thumbnails.enumerated()), id: \.offset) { index, image in
                            Thumbnail(image: image, caption: caption(index, of: check.thumbnails.count), width: 64)
                        }
                    }
                }
            }
        }
    }

    private func details(_ check: AICheckRecord) -> String {
        var parts = [check.offered ? "Offered" : "Not offered"]
        if let milliseconds = check.milliseconds { parts.append("\(milliseconds) ms") }
        if check.joined > 0 { parts.append("\(check.joined) more joined") }
        return parts.joined(separator: " · ")
    }

    private func caption(_ index: Int, of count: Int) -> String {
        index == count - 1 ? "After" : "Frame \(index + 1)"
    }
}
