import SwiftUI

/// A screen's title: Title size, ink, top left, with an optional trailing control. In
/// portrait it sits right under the status bar, 60 from the top; a landscape phone has no
/// status bar, so it keeps 12 from the edge.
struct ScreenTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        .padding(.top, verticalSizeClass == .compact ? Theme.space12 : 0)
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
