import SwiftUI

/// A filter: white, full round, Caption slate. Selected is blush with beet words. The chip
/// is 36 tall drawn, with a 44 pt tap area.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.caption)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.beet : Theme.slate)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.blush : Theme.card, in: Capsule(style: .continuous))
                .frame(minHeight: Theme.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    HStack(spacing: 8) {
        FilterChip(title: "All", isSelected: true) {}
        FilterChip(title: "American", isSelected: false) {}
        FilterChip(title: "British", isSelected: false) {}
    }
    .padding(20)
    .background(Theme.ground)
}
