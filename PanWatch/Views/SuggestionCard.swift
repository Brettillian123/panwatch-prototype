import SwiftUI

/// "Looks like the pasta went in. Start the 9-minute pasta timer?" A detection is always
/// an offer, never an action: a false alarm costs one tap, and a miss costs nothing.
/// An opaque Iron card, no border and no glow; the bar under the buttons drains over the
/// 20 seconds before the offer goes away by itself.
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
        HStack(alignment: .top, spacing: 24) {
            if let before = offer.before, let after = offer.after {
                VStack(alignment: .leading, spacing: Theme.tight) {
                    HStack(alignment: .top, spacing: Theme.tight) {
                        Thumbnail(image: before, caption: "Before", width: 120)
                        Thumbnail(image: after, caption: "After", width: 120)
                    }
                    Text("\(Int((offer.decision.changedFraction * 100).rounded()))% of the pan changed")
                        .font(Theme.detail)
                        .foregroundStyle(Theme.ash)
                }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.tight) {
                Text("Looks like the \(offer.watch.ingredient) went in")
                    .font(Theme.reading)
                    .foregroundStyle(Theme.flour)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("Start the \(offer.watch.timerMinutes)-minute \(offer.watch.timerLabel.lowercased()) timer?")
                    .font(Theme.control)
                    .foregroundStyle(Theme.flour)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: Theme.gap) {
                    Button("Not now") { touched(); dismiss() }
                        .buttonStyle(WordButtonStyle())
                    Button { touched(); accept() } label: {
                        Label("Start timer", systemImage: "timer")
                    }
                    .buttonStyle(WordButtonStyle(kind: .primary))
                }
                .padding(.top, Theme.tight)
                drainingBar
                    .padding(.top, Theme.tight)
            }
        }
        .padding(24)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
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

    /// Ash on the rule color, emptying from the left.
    private var drainingBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Rectangle().fill(Theme.rule)
                Rectangle()
                    .fill(Theme.ash)
                    .frame(width: proxy.size.width * left)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// A small picture of the pan with a caption.
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
            Text(caption)
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
        }
    }
}
