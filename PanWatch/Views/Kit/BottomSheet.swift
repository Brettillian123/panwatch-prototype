import SwiftUI

/// A sheet over a screen: a 45 % ink scrim, then the ground color with radius 20 on top, a
/// grabber, a Title and a 36 close button. Tapping the scrim or the button runs `close`.
struct BottomSheet<Content: View>: View {
    let title: String
    let close: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.ink.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: Theme.space16) {
                Capsule(style: .continuous)
                    .fill(Theme.divider)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.space8)
                    .accessibilityHidden(true)
                HStack {
                    Text(title)
                        .font(Theme.title)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Theme.space8)
                    RoundIconButton(systemImage: "xmark", label: "Close", size: .small, style: .quiet, action: close)
                }
                content
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, Theme.margin)
            .screenColumn()
            .background(
                UnevenRoundedRectangle(topLeadingRadius: Theme.radiusCard, topTrailingRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.ground)
                    .ignoresSafeArea(edges: .bottom)
            )
            .floatingShadow()
        }
    }
}

#Preview {
    BottomSheet(title: "Make a voice", close: {}) {
        QuietButton(title: "Play a sample", systemImage: "play.fill") {}
        PrimaryButton(title: "Save voice") {}
    }
}
