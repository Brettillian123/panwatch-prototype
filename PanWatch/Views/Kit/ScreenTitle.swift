import SwiftUI

/// A screen's title: Title size, ink, top left, with an optional trailing control.
struct ScreenTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.space12) {
            Text(text)
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, Theme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.init(text: text, trailing: { EmptyView() })
    }
}

#Preview {
    VStack(spacing: 20) {
        ScreenTitle("Recipes")
        ScreenTitle(text: "Voices") {
            RoundIconButton(systemImage: "plus", label: "Make a voice", size: .small, style: .quiet) {}
        }
    }
    .padding(20)
    .background(Theme.ground)
}
