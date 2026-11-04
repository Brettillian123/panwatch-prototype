import SwiftUI

/// The recipe menu, at launch and from Recipes or "recipes": the six dishes as a two-column
/// list with a rule between rows, never six matching cards. A tap or two words of a name
/// ("make the rice") picks a dish; on this menu one word ("rice", "eggs") does too.
struct RecipePicker: View {
    let session: CookSession

    /// Dish names in New York, like the step text: a recipe is read like a book.
    private static let dishFont = Font.system(size: 28, weight: .semibold, design: .serif)

    var body: some View {
        MenuScreen(session: session, title: "What are you cooking?") {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: Theme.gap * 2, verticalSpacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, pair in
                        if index > 0 {
                            RowRule()
                                .gridCellUnsizedAxes(.horizontal)
                        }
                        GridRow {
                            ForEach(pair, id: \.title) { recipe in
                                row(recipe)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The dishes two to a row, in the library's order.
    private var rows: [[Recipe]] {
        stride(from: 0, to: Recipe.all.count, by: 2).map { Array(Recipe.all[$0..<min($0 + 2, Recipe.all.count)]) }
    }

    private func row(_ recipe: Recipe) -> some View {
        let current = session.cookUnderWay && recipe.title == session.recipe.title
        return Button {
            // The dish under way goes back to where it was; any other starts at step 1.
            if current {
                session.closeMenu()
            } else {
                session.choose(recipe)
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.tight / 2) {
                Text(recipe.title)
                    .font(Self.dishFont)
                    .foregroundStyle(Theme.flour)
                    .multilineTextAlignment(.leading)
                detail(recipe, current: current)
                    .font(Theme.detail)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// "7 steps · 18-minute rice timer", or "Cooking now · step 3 of 7" on the dish under way.
    private func detail(_ recipe: Recipe, current: Bool) -> Text {
        if current {
            let marker = Text("Cooking now").foregroundStyle(Theme.copper)
            return Text("\(marker) · step \(session.stepIndex + 1) of \(recipe.steps.count)").foregroundStyle(Theme.ash)
        }
        return Text("\(recipe.steps.count) steps · \(timerSummary(recipe))").foregroundStyle(Theme.ash)
    }

    /// "9-minute pasta timer": the timer the camera will offer.
    private func timerSummary(_ recipe: Recipe) -> String {
        guard let watch = recipe.steps.compactMap(\.watch).first else { return "no timer" }
        return "\(watch.timerMinutes)-minute \(watch.timerLabel.lowercased()) timer"
    }
}
