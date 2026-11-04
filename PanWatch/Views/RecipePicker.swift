import SwiftUI

/// The recipe menu, shown before cooking starts and from the Recipes button. Big type,
/// because the phone may already be propped at the back of the stove.
struct RecipePicker: View {
    let session: CookSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What are you cooking?")
                .font(.system(size: 40, weight: .bold))
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(Recipe.all, id: \.title) { recipe in
                        Button { session.choose(recipe) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(recipe.title)
                                    .font(.title.weight(.bold))
                                    .multilineTextAlignment(.leading)
                                Text("\(recipe.steps.count) steps · \(timerSummary(recipe))")
                                    .font(.headline)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                            .padding(18)
                            .background(
                                .white.opacity(recipe.title == session.recipe.title ? 0.22 : 0.12),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.92).ignoresSafeArea())
    }

    /// "9-minute pasta timer": the timer the camera will offer.
    private func timerSummary(_ recipe: Recipe) -> String {
        guard let watch = recipe.steps.compactMap(\.watch).first else { return "no timer" }
        return "\(watch.timerMinutes)-minute \(watch.timerLabel.lowercased()) timer"
    }
}
