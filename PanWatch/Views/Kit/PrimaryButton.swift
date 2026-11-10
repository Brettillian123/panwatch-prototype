import SwiftUI

/// The one main action on a screen: beet, full round, full width, white Body semibold.
/// 56 tall; `.cook` is 68 tall with cook-mode type.
struct PrimaryButton: View {
    enum Size { case regular, cook }

    let title: String
    var systemImage: String? = nil
    var size: Size = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space8) {
                if let systemImage {
                    Image(systemName: systemImage).accessibilityHidden(true)
                }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(size == .cook ? Theme.cookBodyStrong : Theme.bodyStrong)
            .frame(maxWidth: .infinity, minHeight: size == .cook ? 68 : 56)
        }
        .buttonStyle(KitPressStyle(fill: Theme.beet, foreground: .white))
        .accessibilityLabel(title)
    }
}

/// The press look shared by the kit's filled buttons: a capsule of `fill`, darkened while pressed.
struct KitPressStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        KitPressLabel(configuration: configuration, fill: fill, foreground: foreground)
    }
}

private struct KitPressLabel: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? foreground : Theme.slate)
            .padding(.horizontal, Theme.margin)
            .background {
                ZStack {
                    Capsule(style: .continuous).fill(isEnabled ? fill : Theme.fill)
                    if configuration.isPressed { Capsule(style: .continuous).fill(Theme.ink.opacity(0.12)) }
                }
            }
            .contentShape(Capsule(style: .continuous))
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Start cooking", systemImage: "play.fill") {}
        PrimaryButton(title: "Next step", systemImage: "chevron.right", size: .cook) {}
        PrimaryButton(title: "Save voice") {}.disabled(true)
    }
    .padding(20)
    .background(Theme.ground)
}
