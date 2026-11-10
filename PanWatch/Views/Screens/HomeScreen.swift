import SwiftUI

/// Home: the recipes. The title, a search field, one top card (the cook under way to resume,
/// else a suggestion), then sideways rows of small photo cards: favorites, quick ones, all.
/// A card opens the recipe's page; naming a dish by voice still starts it straight away.
struct HomeScreen: View {
    let session: CookSession

    @State private var query = ""
    @State private var favorites = Favorites.load()

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space24) {
                VStack(alignment: .leading, spacing: Theme.space16) {
                    ScreenTitle("Recipes")
                    // The microphone glyph only shows the app listens: dishes are named aloud anywhere on Home.
                    SearchField(placeholder: "Search recipes", text: $query)
                }
                .padding(.horizontal, Theme.margin)

                if searching {
                    results
                } else {
                    topCard
                        .padding(.horizontal, Theme.margin)
                    let favored = favorites.recipes()
                    if !favored.isEmpty {
                        shelf("Favorites", favored)
                    }
                    shelf("Quick ones", Recipe.all.filter(\.isQuick))
                    shelf("All recipes", Recipe.all)
                }
            }
            .padding(.bottom, Theme.space24)
        }
        .scrollDismissesKeyboard(.immediately)
        .screenColumn()
        .onAppear { favorites = Favorites.load() }
    }

    // MARK: Top card

    @ViewBuilder private var topCard: some View {
        if session.cookUnderWay {
            let recipe = session.recipe
            photoCard(recipe) {
                progressCaption(recipe)
                ProgressSegments(done: min(session.stepIndex + 1, recipe.steps.count), total: recipe.steps.count)
                    .padding(.top, Theme.space8)
                PrimaryButton(title: "Resume", systemImage: "play.fill") {
                    session.open(.cook)
                }
                .padding(.top, Theme.space16)
            }
        } else {
            let recipe = suggestion
            photoCard(recipe) {
                Text(recipe.summary)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.slate)
                PrimaryButton(title: "View recipe") {
                    session.open(recipe: recipe)
                }
                .padding(.top, Theme.space16)
            }
        }
    }

    /// The dish to suggest with nothing under way. The cook stats don't record which dishes
    /// were cooked, so it is the first in the menu.
    private var suggestion: Recipe { Recipe.all.first ?? session.recipe }

    private func photoCard<Below: View>(_ recipe: Recipe, @ViewBuilder below: () -> Below) -> some View {
        Card(padded: false) {
            VStack(alignment: .leading, spacing: 0) {
                DishPhoto(recipe: recipe)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.displayTitle)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    below()
                }
                .padding(Theme.space16)
            }
        }
    }

    /// "Step 3 of 5 · Pasta timer 6:42", the timer counting down live; just the step with no timer.
    private func progressCaption(_ recipe: Recipe) -> some View {
        let step = "Step \(min(session.stepIndex + 1, recipe.steps.count)) of \(recipe.steps.count)"
        let timer = session.timers.first(where: { !$0.isDone }) ?? session.timers.first
        let line: Text
        if let timer {
            if timer.isDone {
                line = Text("\(step) · \(timer.label) timer done")
            } else {
                let clock = Text(timerInterval: timer.start...timer.end, pauseTime: timer.pausedAt, countsDown: true)
                line = Text("\(step) · \(timer.label) timer \(clock)")
            }
        } else {
            line = Text(step)
        }
        return line
            .font(Theme.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.slate)
            .lineLimit(1)
    }

    // MARK: Rows

    private func shelf(_ title: String, _ recipes: [Recipe]) -> some View {
        VStack(alignment: .leading, spacing: Theme.space12) {
            Text(title)
                .font(Theme.bodyStrong)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Theme.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.space12) {
                    ForEach(recipes, id: \.title) { recipe in
                        smallCard(recipe, width: 156)
                    }
                }
            }
            .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
        }
    }

    /// Search results: the matches two to a row, or one line saying nothing matched.
    @ViewBuilder private var results: some View {
        let found = Recipe.matching(query)
        if found.isEmpty {
            HStack(spacing: Theme.space12) {
                Text("No recipe matches \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.slate)
                    .lineLimit(2)
                Spacer(minLength: 0)
                QuietButton(title: "Clear") { query = "" }
                    .fixedSize()
            }
            .padding(.horizontal, Theme.margin)
        } else {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: Theme.space12, alignment: .top),
                          GridItem(.flexible(), spacing: Theme.space12, alignment: .top)],
                alignment: .leading,
                spacing: Theme.space16
            ) {
                ForEach(found, id: \.title) { recipe in
                    smallCard(recipe, width: nil)
                }
            }
            .padding(.horizontal, Theme.margin)
        }
    }

    /// A small photo card: the photo 124 tall with the heart on it, the name (up to two
    /// lines) and "10 min · Serves 4". The card opens the recipe's page.
    private func smallCard(_ recipe: Recipe, width: CGFloat?) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                session.open(recipe: recipe)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DishPhoto(recipe: recipe)
                        .frame(height: 124)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
                        .padding(.bottom, Theme.space8)
                    Text(recipe.displayTitle)
                        .font(Theme.bodyStrong)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recipe.summary)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.slate)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(recipe.displayTitle), \(recipe.totalMinutes) minutes, serves \(recipe.serves)")

            HeartButton(isOn: favorites.contains(recipe), label: "Favorite \(recipe.displayTitle)") {
                withAnimation(Theme.motion) { favorites.toggle(recipe) }
                favorites.save()
            }
            .padding(Theme.space8)
        }
        .frame(width: width)
    }
}

#Preview {
    HomeScreen(session: CookSession())
        .background(Theme.ground)
}
