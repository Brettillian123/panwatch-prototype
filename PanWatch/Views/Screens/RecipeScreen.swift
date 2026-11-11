import SwiftUI

/// One recipe's page, for `session.viewedRecipe`: the photo on ink with a back button and a
/// heart, then a sheet with the name, three facts, Ingredients or Steps as grouped rows, and
/// Start cooking held above the home indicator. The photo slides away slower than the list.
/// By voice, "start cooking" starts it and "back" returns to Home (both in `CookSession`).
struct RecipeScreen: View {
    let session: CookSession

    private enum Part: Hashable { case ingredients, steps }

    @State private var part = Part.ingredients
    @State private var favorites = Favorites.load()

    /// True while the dark photo is under the status bar, so the root shows the clock in white.
    @Binding var photoOnTop: Bool

    private static let heroHeight: CGFloat = 345

    private var recipe: Recipe { session.viewedRecipe ?? session.recipe }

    /// This dish is the one under way, so the button goes back to its step.
    private var isUnderWay: Bool { session.cookUnderWay && session.recipe.title == recipe.title }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                sheet
                    .padding(.top, -Theme.radiusCard)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top < Self.heroHeight - 60
        } action: { _, onTop in
            photoOnTop = onTop
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { topButtons }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: isUnderWay ? "Resume cooking" : "Start cooking", systemImage: "play.fill") {
                session.startCooking()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, Theme.space12)
            .padding(.bottom, Theme.space8)
            .background(Theme.ground)
        }
        .background(Theme.ground)
        .screenColumn()
        .onAppear {
            favorites = Favorites.load()
            photoOnTop = true
        }
    }

    /// The photo, aspect-filled on ink. Pulled down it grows; scrolled up it moves at half speed.
    private var hero: some View {
        DishPhoto(recipe: recipe)
            .frame(maxWidth: .infinity)
            .frame(height: Self.heroHeight)
            .clipped()
            .background(Theme.ink)
            .visualEffect { content, proxy in
                let y = proxy.frame(in: .scrollView).minY
                return content
                    .scaleEffect(y > 0 ? 1 + y / Self.heroHeight : 1, anchor: .bottom)
                    .offset(y: y < 0 ? -y / 2 : 0)
            }
            .accessibilityHidden(true)
    }

    private var topButtons: some View {
        HStack {
            RoundIconButton(systemImage: "chevron.left", label: "Back") {
                session.noteTouch()
                session.closeMenu()
            }
            Spacer()
            HeartButton(isOn: favorites.contains(recipe), label: "Favorite \(recipe.displayTitle)", size: .medium) {
                withAnimation(Theme.motion) { favorites.toggle(recipe) }
                favorites.save()
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.space8)
    }

    @ViewBuilder private var facts: some View {
        InfoChip(text: "\(recipe.totalMinutes) min", systemImage: "clock")
        InfoChip(text: "Serves \(recipe.serves)", systemImage: "person.2")
        InfoChip(text: "\(recipe.steps.count) steps", systemImage: "list.bullet")
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            Text(recipe.displayTitle)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // The category is one more chip, only when the row still fits on one line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.space8) {
                    facts
                    InfoChip(text: recipe.category.title, systemImage: recipe.category.symbol)
                }
                HStack(spacing: Theme.space8) { facts }
            }
            SegmentedPicker(
                options: [(value: Part.ingredients, title: "Ingredients"), (value: Part.steps, title: "Steps")],
                selection: $part
            )
            .padding(.top, Theme.space8)
            switch part {
            case .ingredients:
                GroupedRows {
                    ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { _, line in
                        Row(label: line.name, value: line.amount.isEmpty ? nil : line.amount)
                    }
                }
            case .steps:
                GroupedRows {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        Row(label: step.instruction) {
                            Text("\(index + 1)")
                                .font(Theme.bodyStrong)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                                .frame(width: 24, alignment: .leading)
                                .accessibilityLabel("Step \(index + 1)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.space24)
        .padding(.bottom, Theme.space24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.ground,
            in: UnevenRoundedRectangle(topLeadingRadius: Theme.radiusCard, topTrailingRadius: Theme.radiusCard, style: .continuous)
        )
    }
}

#Preview {
    RecipeScreen(session: CookSession(), photoOnTop: .constant(true))
        .background(Theme.ground)
}
