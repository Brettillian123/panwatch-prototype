import SwiftUI

/// A slider: a 6 track in ink 7 %, a 28 white thumb with the control shadow. An amount
/// fills beet up to the thumb; a balance (`fills: false`) has no fill. Optional end labels
/// in Caption slate.
struct AppSlider: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var fills = true
    var lowLabel: String? = nil
    var highLabel: String? = nil

    private let thumb: CGFloat = 28

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = max(proxy.size.width - thumb, 1)
                let fraction = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne)
                let x = width * CGFloat(min(max(fraction, 0), 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fill).frame(height: 6)
                    if fills {
                        Capsule().fill(Theme.beet).frame(width: x + thumb / 2, height: 6)
                    }
                    Circle()
                        .fill(Theme.card)
                        .frame(width: thumb, height: thumb)
                        .controlShadow()
                        .offset(x: x)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { drag in
                        let f = Double(min(max((drag.location.x - thumb / 2) / width, 0), 1))
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                )
            }
            .frame(height: Theme.minTarget)
            if lowLabel != nil || highLabel != nil {
                HStack {
                    Text(lowLabel ?? "")
                    Spacer()
                    Text(highLabel ?? "")
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.slate)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text("\(Int(((value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne) * 100).rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 10
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State var speed = 0.5
        @State var blend = 0.3
        var body: some View {
            VStack(spacing: 20) {
                AppSlider(label: "Speed", value: $speed)
                AppSlider(label: "Blend", value: $blend, fills: false, lowLabel: "Ava", highLabel: "Jamie")
            }
            .padding(20)
            .background(Theme.ground)
        }
    }
    return Demo()
}
