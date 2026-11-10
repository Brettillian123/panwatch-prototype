import SwiftUI

/// One recipe's page, for `session.viewedRecipe`. For now a titled placeholder with the
/// photo and Start cooking; the Recipe piece rebuilds it here.
struct RecipeScreen: View {
    let session: CookSession

    private var recipe: Recipe { session.viewedRecipe ?? session.recipe }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            HStack {
                RoundIconButton(systemImage: "chevron.left", label: "Back") {
                    session.noteTouch()
                    session.closeMenu()
                }
                Spacer()
            }
            DishPhoto(recipe: recipe)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            ScreenTitle(recipe.title)
            Text("\(recipe.steps.count) steps")
                .font(Theme.caption)
                .foregroundStyle(Theme.slate)
            Spacer(minLength: 0)
            PrimaryButton(title: "Start cooking", systemImage: "play.fill") {
                session.startCooking()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, Theme.margin)
        .screenColumn()
    }
}

#Preview {
    RecipeScreen(session: CookSession())
        .background(Theme.ground)
}
