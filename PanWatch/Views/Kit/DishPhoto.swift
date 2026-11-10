import SwiftUI
import UIKit

/// A dish's photo: the asset `dish-<slug>` when the app has it, else a plain soft tile,
/// blush or sky by the recipe's place in the menu, with `fork.knife` in slate. It fills
/// the frame it is given; the caller sets the size and the corner radius.
struct DishPhoto: View {
    let recipe: Recipe

    var body: some View {
        if let image = UIImage(named: recipe.photoName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel(recipe.title)
        } else {
            ZStack {
                (recipe.menuIndex.isMultiple(of: 2) ? Theme.blush : Theme.sky)
                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.slate)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .accessibilityLabel(recipe.title)
        }
    }
}

#Preview {
    ScrollView(.horizontal) {
        HStack(spacing: 12) {
            ForEach(Recipe.all.indices, id: \.self) { index in
                DishPhoto(recipe: Recipe.all[index])
                    .frame(width: 156, height: 124)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
            }
        }
        .padding(20)
    }
    .background(Theme.ground)
}
