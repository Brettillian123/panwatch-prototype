import SwiftUI

/// "Looks like the pasta went in. Start a 9-minute timer?" A detection is always an
/// offer, never an action: a false alarm costs one tap, and a miss costs nothing.
struct SuggestionCard: View {
    let offer: TimerSuggestion
    let accept: () -> Void
    let dismiss: () -> Void
    /// Counts a tap on the card's buttons; the card closing by itself isn't a touch.
    var touched: () -> Void = {}

    var body: some View {
        HStack(spacing: 26) {
            if let before = offer.before, let after = offer.after {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Thumbnail(image: before, caption: "Before", width: 120)
                        Thumbnail(image: after, caption: "After", width: 120)
                    }
                    Text("\(Int((offer.decision.changedFraction * 100).rounded()))% of the pan changed")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Looks like the \(offer.watch.ingredient) went in")
                    .font(.system(size: 30, weight: .bold))
                Text("Start a \(offer.watch.timerMinutes)-minute \(offer.watch.timerLabel.lowercased()) timer?")
                    .font(.title2)
                HStack(spacing: 12) {
                    Button { touched(); dismiss() } label: {
                        Text("Not now")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    Button { touched(); accept() } label: {
                        Label("Start timer", systemImage: "timer")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .controlSize(.extraLarge)
                Text("Say “yes”, or press a volume button")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.green.opacity(0.7), lineWidth: 2)
        )
        .padding(40)
        .task(id: offer.id) {
            // Unanswered offers go away on their own; the cook may just be busy.
            do {
                try await Task.sleep(for: .seconds(20))
                dismiss()
            } catch {}
        }
    }
}

/// A small picture of the pan with a caption.
struct Thumbnail: View {
    let image: CGImage
    let caption: String
    let width: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
