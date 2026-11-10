import SwiftUI

/// A white card, radius 20, with the card shadow. Its content sets its own padding, so a
/// photo can run to the edges; `padded` adds the usual 16.
struct Card<Content: View>: View {
    var padded = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padded ? Theme.space16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .cardShadow()
    }
}

#Preview {
    Card {
        VStack(alignment: .leading, spacing: 4) {
            Text("Garlic butter pasta").font(Theme.bodyStrong).foregroundStyle(Theme.ink)
            Text("Step 3 of 5 · Pasta timer 6:42").font(Theme.caption).foregroundStyle(Theme.slate)
        }
    }
    .padding(20)
    .background(Theme.ground)
}
