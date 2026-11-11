import SwiftUI

/// A shelf's heading on Home: Body Strong ink, and, when it opens a full list, a chevron
/// with the whole row as a 44 pt tap target.
struct ShelfHeading: View {
    let title: String
    /// Nil for a heading that opens nothing.
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                HStack(spacing: Theme.space8) {
                    label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.slate)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.minTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), see all")
        } else {
            label.frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
        }
    }

    private var label: some View {
        Text(title)
            .font(Theme.bodyStrong)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading) {
        ShelfHeading(title: "Favorites")
        ShelfHeading(title: "Pasta and grains") {}
    }
    .padding(20)
    .background(Theme.ground)
}
