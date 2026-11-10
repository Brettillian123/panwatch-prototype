import SwiftUI

/// The look of Sous Vision, from `handoff/design/editorial-v3/README.md`: one face (the
/// system font), three sizes, two weights, a light cool ground, beet for the one main action.
/// This file is the single source; the components in `Views/Kit` read only from it.
enum Theme {
    // MARK: Color

    /// Cool ground: under every screen, cook mode included.
    static let ground = rgb(0xF3F5F8)
    /// Cards, rows, the tab bar, round buttons, chips.
    static let card = rgb(0xFFFFFF)
    /// Ink navy: text, and the now-playing card.
    static let ink = rgb(0x14203A)
    /// The one main action, and the selected state.
    static let beet = rgb(0xC2185B)
    /// The selected tab and chip, the timer offer, the make-a-voice card.
    static let blush = rgb(0xF6DCE6)
    /// Info chips, play buttons.
    static let sky = rgb(0xCFE0F1)
    /// Second text.
    static let slate = rgb(0x5A6478)
    /// The second text color on the ink card: white at 72 %.
    static let softWhite = Color.white.opacity(0.72)
    /// Ink at 7 %: the search field, slider tracks, the segmented control, quiet buttons.
    static let fill = ink.opacity(0.07)
    /// Ink at 10 %: the one divider.
    static let divider = ink.opacity(0.10)

    // MARK: Type
    // Three steps and two weights, the system font only. Digits add `.monospacedDigit()`.

    /// 28 semibold: the screen title, a recipe's name, a sheet's title.
    static let title = Font.system(size: 28, weight: .semibold)
    /// 17 regular: rows, values, the search placeholder.
    static let body = Font.system(size: 17, weight: .regular)
    /// 17 semibold: names, buttons.
    static let bodyStrong = Font.system(size: 17, weight: .semibold)
    /// 13 regular: details under a name, chips, tab labels.
    static let caption = Font.system(size: 13, weight: .regular)

    /// Cook mode, read from across the counter: 34 semibold, the step and the timer digits.
    static let cookTitle = Font.system(size: 34, weight: .semibold)
    /// Cook mode 20 regular.
    static let cookBody = Font.system(size: 20, weight: .regular)
    /// Cook mode 20 semibold: buttons, the offer's question.
    static let cookBodyStrong = Font.system(size: 20, weight: .semibold)
    /// Cook mode 15 regular: "Step 3 of 5", "Pasta timer", the camera chip.
    static let cookCaption = Font.system(size: 15, weight: .regular)

    // MARK: Shape and spacing

    /// Cards, sheets, the camera box.
    static let radiusCard: CGFloat = 20
    /// Fields and tiles.
    static let radiusField: CGFloat = 14
    /// The side margin of every screen.
    static let margin: CGFloat = 20
    /// Inside a card; between groups.
    static let space16: CGFloat = 16
    /// Inside a group.
    static let space12: CGFloat = 12
    /// Inside a group, tight.
    static let space8: CGFloat = 8
    /// Before a section heading.
    static let space24: CGFloat = 24
    /// The smallest tap target.
    static let minTarget: CGFloat = 44
    /// The widest a non-cook screen's column gets, in landscape.
    static let columnMax: CGFloat = 520

    // MARK: Motion

    /// Every state change.
    static let motion = Animation.snappy(duration: 0.25)
    /// The offer, the one entrance.
    static let entrance = Animation.snappy(duration: 0.3)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Shadows: one navy in three steps

extension View {
    /// Control: 0 1 4, 16 %.
    func controlShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.16), radius: 2, x: 0, y: 1)
    }

    /// Card: 0 6 20, 8 %.
    func cardShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    /// Floating: 0 12 32, 20 % (the tab bar, a sheet).
    func floatingShadow() -> some View {
        shadow(color: Theme.ink.opacity(0.20), radius: 16, x: 0, y: 12)
    }

    /// A non-cook screen's content: full width in portrait, a centered column at most 520 wide in landscape.
    func screenColumn() -> some View {
        frame(maxWidth: Theme.columnMax)
            .frame(maxWidth: .infinity)
    }
}
