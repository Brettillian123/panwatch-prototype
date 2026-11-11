import SwiftUI

/// The recipe list: a title, a sideways row of filter chips (All, Under 20 min, Stovetop,
/// then each category), and the recipes as rows. A shelf heading on Home opens it on that
/// shelf; a dish asked for by voice that matches nothing opens it on the search for it; a
/// name several dishes share opens it on those dishes.
struct RecipeListScreen: View {
    let session: CookSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space16) {
                HStack(spacing: Theme.space12) {
                    RoundIconButton(systemImage: "chevron.left", label: "Back") {
                        session.noteTouch()
                        session.closeMenu()
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, Theme.space8)

                ScreenTitle(title)
                    .padding(.horizontal, Theme.margin)

                if session.listChoice.isEmpty { chips }

                rows
            }
            .padding(.bottom, Theme.space24)
        }
        .screenColumn()
    }

    private var searching: Bool { !session.listQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    private var title: String {
        if !session.listChoice.isEmpty { return "Which one?" }
        if searching { return "\u{201C}\(session.listQuery)\u{201D}" }
        return session.listFilter == .all ? "All recipes" : session.listFilter.title
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.space8) {
                ForEach(RecipeFilter.chips, id: \.self) { filter in
                    FilterChip(title: filter.title, isSelected: session.listFilter == filter) {
                        withAnimation(Theme.motion) { session.listFilter = filter }
                    }
                }
            }
        }
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    @ViewBuilder private var rows: some View {
        let recipes = session.listRecipes
        if recipes.isEmpty {
            HStack(spacing: Theme.space12) {
                Text(searching ? "No recipe matches \u{201C}\(session.listQuery)\u{201D}" : "No recipes here yet")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.slate)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if searching || session.listFilter != .all {
                    QuietButton(title: "Show all") {
                        session.listQuery = ""
                        session.listFilter = .all
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.margin)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(recipes, id: \.id) { recipe in
                    RecipeRow(entry: recipe) { session.open(entry: recipe) }
                    if recipe.id != recipes.last?.id {
                        Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 76)
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
        }
    }
}

#Preview {
    RecipeListScreen(session: CookSession())
        .background(Theme.ground)
}
