import SwiftUI

/// A second action: ink 7 % fill, ink Body semibold words, 50 tall (68 in cook mode).
struct QuietButton: View {
    let title: String
    var systemImage: String? = nil
    var size: PrimaryButton.Size = .regular
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
            .frame(maxWidth: .infinity, minHeight: size == .cook ? 68 : 50)
        }
        .buttonStyle(KitPressStyle(fill: Theme.fill, foreground: Theme.ink))
        .accessibilityLabel(title)
    }
}

#Preview {
    VStack(spacing: 16) {
        QuietButton(title: "Play a sample", systemImage: "play.fill") {}
        QuietButton(title: "Back", size: .cook) {}
    }
    .padding(20)
    .background(Theme.ground)
}
