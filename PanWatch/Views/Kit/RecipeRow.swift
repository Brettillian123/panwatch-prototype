import SwiftUI

/// One recipe in a list: a 64 pt photo with the field radius, the name in Body Strong ink
/// (up to two lines) and "20 min · Serves 4" in Caption slate. The whole row is the button.
struct RecipeRow: View {
    let entry: RecipeEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space12) {
                DishPhoto(entry: entry)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayTitle)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(entry.summary)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.slate)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.slate)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.space8)
            .frame(minHeight: Theme.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.displayTitle), \(entry.totalMinutes) minutes, serves \(entry.serves)")
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(RecipeIndex.bundled.entries.prefix(3)) { entry in
            RecipeRow(entry: entry) {}
        }
    }
    .padding(20)
    .background(Theme.ground)
}
