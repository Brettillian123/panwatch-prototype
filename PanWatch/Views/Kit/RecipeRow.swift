import SwiftUI

/// One recipe in a list: a 64 pt photo with the field radius, the name in Body Strong ink
/// (up to two lines) and "20 min · Serves 4" in Caption slate. The whole row is the button.
struct RecipeRow: View {
    let recipe: Recipe
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space12) {
                DishPhoto(recipe: recipe)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.displayTitle)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(recipe.summary)
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
        .accessibilityLabel("\(recipe.displayTitle), \(recipe.totalMinutes) minutes, serves \(recipe.serves)")
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(Recipe.all.prefix(3), id: \.id) { recipe in
            RecipeRow(recipe: recipe) {}
        }
    }
    .padding(20)
    .background(Theme.ground)
}
