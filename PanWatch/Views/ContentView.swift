import SwiftUI

// MARK: - Menus

/// A full-screen menu over the cook screen: a 44 pt title, its rows, and along the bottom
/// the same Say line as the cook screen with a worded Done beside it, bottom right. Done
/// and "done" are the one way out.
struct MenuScreen<Content: View>: View {
    let session: CookSession
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.gap) {
            Text(title)
                .font(Theme.reading)
                .foregroundStyle(Theme.flour)
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: Theme.gap) {
                SayLine(session: session)
                Button("Done") {
                    session.noteTouch()
                    session.closeMenu()
                }
                .buttonStyle(WordButtonStyle())
            }
        }
        .padding(.top, Theme.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.iron)
    }
}

/// The 1 px rule between list rows: Flour at 12%, never a box.
struct RowRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A whole list row as one target: pressed lifts it with the rule color, like a secondary
/// button, so a tap shows where it landed.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, Theme.tight)
            .background(
                configuration.isPressed ? Theme.rule : Color.clear,
                in: RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
            )
            .contentShape(Rectangle())
    }
}
