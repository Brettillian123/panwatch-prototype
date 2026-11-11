import SwiftUI

/// "Looks like the pasta went in. Start a 9-minute timer?" A detection is always an offer,
/// never an action: a false alarm costs one tap, and a miss costs nothing. Blush, radius 20,
/// 164 tall, in place of the timer card and the buttons. A thin beet line along the bottom
/// edge drains over the 20 seconds before the offer goes away by itself. The before and
/// after pictures are in the debug panel.
struct SuggestionCard: View {
    let offer: TimerSuggestion
    let accept: () -> Void
    let dismiss: () -> Void
    /// Counts a tap on the card's buttons; the card closing by itself isn't a touch.
    var touched: () -> Void = {}

    /// How long an unanswered offer stays up.
    private static let timeout = 20.0
    /// The share of the wait still left, 1 to 0. The card is rebuilt for each offer.
    @State private var left: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(offer.offer.caption)
                .font(Theme.cookCaption)
                .foregroundStyle(Theme.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(offer.offer.question)
                .font(Theme.cookBodyStrong)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Theme.space8)
            HStack(spacing: Theme.space12) {
                Button { touched(); dismiss() } label: {
                    Text("Not now")
                        .font(Theme.cookBodyStrong)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 68)
                }
                .buttonStyle(KitPressStyle(fill: Theme.card, foreground: Theme.ink))
                .accessibilityLabel("Not now")
                PrimaryButton(title: "Start timer", size: .cook) { touched(); accept() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 164, maxHeight: 164, alignment: .topLeading)
        .background(Theme.blush, in: shape)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Theme.beet)
                    .frame(width: proxy.size.width * left, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .accessibilityHidden(true)
        }
        .clipShape(shape)
        .onAppear {
            withAnimation(.linear(duration: Self.timeout)) { left = 0 }
        }
        .task(id: offer.id) {
            // Unanswered offers go away on their own; the cook may just be busy.
            do {
                try await Task.sleep(for: .seconds(Self.timeout))
                dismiss()
            } catch {}
        }
    }
}

/// A small picture of the pan with a caption, in the debug panel.
struct Thumbnail: View {
    let image: CGImage
    let caption: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(caption)
                .font(Theme.caption)
                .foregroundStyle(Theme.slate)
        }
    }
}
