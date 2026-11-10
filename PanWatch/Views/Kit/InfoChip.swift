import SwiftUI

/// A fact about a recipe: sky, full round, 32 tall, a 16 glyph and Caption ink. Not tappable.
struct InfoChip: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(text).font(Theme.caption).monospacedDigit().lineLimit(1)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, Theme.space12)
        .frame(minHeight: 32)
        .background(Theme.sky, in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack(spacing: 8) {
        InfoChip(text: "20 min", systemImage: "clock")
        InfoChip(text: "Serves 4", systemImage: "person.2")
        InfoChip(text: "5 steps", systemImage: "list.bullet")
    }
    .padding(20)
    .background(Theme.ground)
}
