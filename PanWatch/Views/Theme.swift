import SwiftUI

/// The look of Sous Vision, from `handoff/design/ui-voice-first.md` section 4.
///
/// Sizes are fixed points, not Dynamic Type text styles, on purpose: they are set by the
/// reading distance (the phone stands at the back of the stove, a meter from the cook) and
/// already exceed the large accessibility sizes. Every control still carries a word, which
/// VoiceOver reads, and menus reflow rather than truncate.
enum Theme {
    // MARK: Color
    // Five colors from the kitchen and one accent, always opaque: no blur, no glass, so
    // Reduce Transparency and Increase Contrast change nothing. The only text pairs are
    // these on Iron, and Iron on Copper or Chili; Flour on Copper (2.8:1) never happens.

    /// Cast iron. Every panel, card, bar, strip and menu; the words on a filled button.
    static let iron = rgb(0x16140F)
    /// Main text: step text, digits, labels, button words. 15.6:1 on Iron.
    static let flour = rgb(0xF2ECDF)
    /// Second text, the draining bar, "Not listening". 7.0:1 on Iron.
    static let ash = rgb(0xA69F92)
    /// The camera line when it is watching or has seen the pan. Words only, never a fill. 5.7:1.
    static let herb = rgb(0x6A9C4B)
    /// Done or alert: a finished timer's words and edge rule, a denied permission. Words and
    /// rules only, never a fill, and it never flashes. 5.2:1.
    static let chili = rgb(0xE85A45)
    /// The accent, from the pan rim: filled primary buttons, "Heard", the level bar. 5.7:1.
    static let copper = rgb(0xC47F3A)
    /// The one rule between rows, and the lift on a secondary button: Flour at 12%.
    static let rule = flour.opacity(0.12)

    /// The one accent for primary actions (Next step, Start timer, Start watching, Draw a box).
    static let primary = copper
    /// The one color for done or alert.
    static let alert = chili

    // MARK: Type
    // Three sizes at a ratio of about 1.55, plus one size for the countdown.

    /// 18 pt: near-phone detail, never required (the eyebrow, captions).
    static let detail = Font.system(size: 18, weight: .regular)
    /// 28 pt: buttons, the camera line, timer labels, menu rows.
    static let control = Font.system(size: 28, weight: .semibold)
    /// 44 pt: anything read from a meter away (the Say line's phrase, the offer, "Rice is done").
    static let reading = Font.system(size: 44, weight: .semibold)
    /// 44 pt New York: the step text, read like a book.
    static let step = Font.system(size: 44, weight: .semibold, design: .serif)
    /// 64 pt: the countdown, the one number size.
    static let digits = Font.system(size: 64, weight: .bold).monospacedDigit()
    /// 44 pt: the countdown once three timers share the column.
    static let compactDigits = Font.system(size: 44, weight: .bold).monospacedDigit()

    // MARK: Geometry

    /// Any tap target.
    static let target: CGFloat = 44
    /// A target a messy thumb hits: offer buttons, Clear, Done, the Say line.
    static let bigTarget: CGFloat = 60
    /// The bottom bar's buttons.
    static let barHeight: CGFloat = 64
    /// Inside a text group.
    static let tight: CGFloat = 8
    /// Between targets and between groups.
    static let gap: CGFloat = 16
    /// Thumbnails and the level bar.
    static let thumbRadius: CGFloat = 4
    /// Buttons.
    static let buttonRadius: CGFloat = 12
    /// Panels and cards.
    static let panelRadius: CGFloat = 20

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

/// An opaque Iron panel with the panel radius.
extension View {
    func ironPanel(padding: CGFloat = Theme.gap) -> some View {
        self
            .padding(padding)
            .background(Theme.iron, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}

/// The one button: a word at 28 pt on an opaque shape with the button radius.
/// Primary is Copper with Iron words; secondary is Iron lifted by the rule color, with
/// Flour words, so it reads both on the picture and on an Iron panel. Pressed darkens a
/// primary and edges a secondary in Copper; disabled turns the words Ash on plain Iron.
struct WordButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    var kind: Kind = .secondary
    var height: CGFloat = Theme.bigTarget

    func makeBody(configuration: Configuration) -> some View {
        WordButtonLabel(configuration: configuration, kind: kind, height: height)
    }
}

private struct WordButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let kind: WordButtonStyle.Kind
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
        let pressed = configuration.isPressed
        configuration.label
            .font(Theme.control)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(minWidth: Theme.bigTarget, minHeight: height)
            .background {
                ZStack {
                    shape.fill(fill)
                    if kind == .secondary && isEnabled { shape.fill(Theme.rule) }
                    if pressed && kind == .primary && isEnabled { shape.fill(Theme.iron.opacity(0.3)) }
                    if pressed && kind == .secondary { shape.strokeBorder(Theme.copper, lineWidth: 3) }
                }
            }
            .contentShape(shape)
    }

    private var fill: Color {
        kind == .primary && isEnabled ? Theme.primary : Theme.iron
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.ash }
        return kind == .primary ? Theme.iron : Theme.flour
    }
}
