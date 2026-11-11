import SwiftUI
import UIKit

/// A dish's photo: the asset `dish-<slug>` when the app has it, else a plain soft tile in
/// the category's color (blush or sky, alternating shelf by shelf) with the category's
/// symbol in slate, so a shelf of dishes still waiting for photos reads as one deliberate
/// run. The photo is decoded off the main thread, the tile showing until it is ready, so a
/// long list scrolls without stalls. It fills the frame it is given; the caller sets the
/// size and the corner radius.
struct DishPhoto: View {
    let id: String
    let title: String
    let category: RecipeCategory
    /// From the index: false skips the asset lookup altogether.
    let hasPhoto: Bool

    init(entry: RecipeEntry) {
        self.init(id: entry.id, title: entry.title, category: entry.category, hasPhoto: entry.hasPhoto)
    }

    init(recipe: Recipe) {
        self.init(id: recipe.id, title: recipe.title, category: recipe.category,
                  hasPhoto: RecipeIndex.bundled.entry(id: recipe.id)?.hasPhoto ?? true)
    }

    init(id: String, title: String, category: RecipeCategory, hasPhoto: Bool) {
        self.id = id
        self.title = title
        self.category = category
        self.hasPhoto = hasPhoto
    }

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
            } else {
                (category.tileIsBlush ? Theme.blush : Theme.sky)
                Image(systemName: category.symbol)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.slate)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(title)
        .task(id: id) {
            guard hasPhoto else { return }
            let name = "dish-" + id
            let decoded = await Task.detached(priority: .userInitiated) {
                UIImage(named: name)?.preparingForDisplay()
            }.value
            withAnimation(Theme.motion) { image = decoded }
        }
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            ForEach(RecipeIndex.bundled.entries) { entry in
                DishPhoto(entry: entry)
                    .frame(width: 156, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
            }
        }
        .padding(20)
    }
    .background(Theme.ground)
}
