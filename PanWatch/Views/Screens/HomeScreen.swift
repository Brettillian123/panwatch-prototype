import SwiftUI

/// Home: the recipe book. The title, a search field, one top card (the cook under way to
/// resume, else a suggestion), then sideways shelves of small photo cards: favorites, quick
/// ones, then one per category. A shelf shows at most ten; its heading opens the full list.
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
                        .padding(.bottom, -4)
                    // Dishes are named aloud anywhere on Home; the microphone shows the app is
                    // listening, and a tap turns listening off or on, as the chip in cook mode does.
                    SearchField(placeholder: "Search recipes", text: $query, listening: session.listeningOn) {
                        session.noteTouch()
                        session.toggleListening()
                    }
                    if !searching { topCard }
                }
                .padding(.horizontal, Theme.margin)

                if searching {
                    results
                } else {
                    LazyVStack(alignment: .leading, spacing: Theme.space24) {
                        let favored = favorites.recipes()
                        if !favored.isEmpty {
                            shelf("Favorites", favored)
                        }
                        shelf("Quick ones", RecipeIndex.bundled.filtered(.quick), opens: .quick)
                        ForEach(Self.shelves(), id: \.title) { shelf in
                            self.shelf(shelf.title, shelf.recipes, opens: shelf.filter)
                        }
                    }
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

    /// The dish to suggest with nothing under way: one not cooked yet, else the one cooked
    /// longest ago.
    private var suggestion: Recipe {
        session.history.suggestion(from: RecipeIndex.bundled.entries).flatMap { Recipe.withID($0.id) } ?? session.recipe
    }

    /// Shelves of at least this many get their own category; smaller ones share "More recipes".
    private static let shelfMinimum = 3
    /// Cards on one shelf; the heading's list has the rest.
    private static let shelfLimit = 10

    /// One shelf per category with enough recipes, then the rest together, so six recipes
    /// still fill a shelf and sixty don't make one endless.
    private struct Shelf {
        let title: String
        let recipes: [RecipeEntry]
        let filter: RecipeFilter
    }

    private static func shelves(_ recipes: [RecipeEntry] = RecipeIndex.bundled.entries) -> [Shelf] {
        var result: [Shelf] = []
        var rest: [RecipeEntry] = []
        for category in RecipeCategory.allCases {
            let inIt = recipes.filter { $0.category == category }
            if inIt.count >= shelfMinimum {
                result.append(Shelf(title: category.title, recipes: inIt, filter: .category(category)))
            } else {
                rest += inIt
            }
        }
        if !rest.isEmpty { result.append(Shelf(title: result.isEmpty ? "All recipes" : "More recipes", recipes: rest, filter: .all)) }
        return result
    }

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
                let clock = countdown(timer)
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

    private func shelf(_ title: String, _ recipes: [RecipeEntry], opens filter: RecipeFilter? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.space8) {
            ShelfHeading(title: title, action: opener(filter))
            .padding(.horizontal, Theme.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.space12) {
                    ForEach(recipes.prefix(Self.shelfLimit), id: \.id) { recipe in
                        smallCard(recipe, width: 156)
                    }
                }
            }
            .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
        }
    }

    /// What a shelf's heading does: opens the list on its filter; nothing for Favorites.
    private func opener(_ filter: RecipeFilter?) -> (() -> Void)? {
        guard let filter else { return nil }
        return {
            session.noteTouch()
            session.openList(filter)
        }
    }

    /// Search results: the matches as rows, or one line saying nothing matched.
    @ViewBuilder private var results: some View {
        let found = RecipeIndex.bundled.search(query)
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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(found, id: \.id) { recipe in
                    RecipeRow(entry: recipe) { session.open(entry: recipe) }
                }
            }
            .padding(.horizontal, Theme.margin)
        }
    }

    /// A small photo card: the photo 124 tall with the heart on it, the name (up to two
    /// lines) and "10 min · Serves 4". The card opens the recipe's page.
    private func smallCard(_ recipe: RecipeEntry, width: CGFloat?) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                session.open(entry: recipe)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    DishPhoto(entry: recipe)
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
            .accessibilityLabel("\(recipe.displayTitle), \(recipe.spokenTime)" + (recipe.serves.map { ", serves \($0)" } ?? ""))

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
