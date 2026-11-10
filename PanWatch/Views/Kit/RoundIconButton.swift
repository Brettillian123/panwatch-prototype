import SwiftUI

/// A round button holding one SF Symbol. The circle is 36, 44 or 52 across; a 36 one still
/// takes a 44 pt tap area.
struct RoundIconButton: View {
    enum Size: CGFloat { case small = 36, medium = 44, large = 52 }
    enum Style { case card, quiet, sky, beet }

    let systemImage: String
    let label: String
    var size: Size = .medium
    var style: Style = .card
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size.rawValue * 0.4, weight: .semibold))
                .foregroundStyle(style == .beet ? Color.white : Theme.ink)
                .frame(width: size.rawValue, height: size.rawValue)
                .background(fill, in: Circle())
                .modifier(RoundShadow(on: style == .card))
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var fill: Color {
        switch style {
        case .card: Theme.card
        case .quiet: Theme.fill
        case .sky: Theme.sky
        case .beet: Theme.beet
        }
    }
}

private struct RoundShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.controlShadow() } else { content }
    }
}

#Preview {
    HStack(spacing: 16) {
        RoundIconButton(systemImage: "xmark", label: "Close", size: .small, style: .quiet) {}
        RoundIconButton(systemImage: "chevron.left", label: "Back") {}
        RoundIconButton(systemImage: "pause.fill", label: "Pause", size: .large, style: .quiet) {}
        RoundIconButton(systemImage: "play.fill", label: "Play", style: .sky) {}
    }
    .padding(20)
    .background(Theme.ground)
}
