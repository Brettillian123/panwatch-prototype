import SwiftUI

/// A recipe's favorite toggle: a white circle (36 or 44 across, always a 44 pt tap area)
/// holding a heart, beet and filled when on, an ink outline when off.
struct HeartButton: View {
    let isOn: Bool
    var label = "Favorite"
    var size: RoundIconButton.Size = .small
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "heart.fill" : "heart")
                .font(.system(size: size.rawValue * 0.42, weight: .semibold))
                .foregroundStyle(isOn ? Theme.beet : Theme.ink)
                .frame(width: size.rawValue, height: size.rawValue)
                .background(Theme.card, in: Circle())
                .controlShadow()
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    HStack(spacing: 16) {
        HeartButton(isOn: true) {}
        HeartButton(isOn: false) {}
        HeartButton(isOn: true, size: .medium) {}
    }
    .padding(20)
    .background(Theme.sky)
}
