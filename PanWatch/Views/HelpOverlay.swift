import SwiftUI

/// "What can I say": a bottom sheet over the screen it was opened from. First the phrases
/// that work right there (in cook mode, the ones the old Say line cycled through); then every group, the ones about that screen first,
/// each in its own grouped rows. Closes on "done", the close button, a tap on the scrim, or
/// by itself after 30 seconds.
struct HelpOverlay: View {
    let session: CookSession

    /// A heading and its phrases.
    private struct Block: Identifiable {
        let id: String
        let title: String
        let phrases: [String]
    }

    var body: some View {
        GeometryReader { proxy in
            BottomSheet(title: "What you can say", close: { session.noteTouch(); session.closeMenu() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.space16) {
                        ForEach(blocks) { block in
                            VStack(alignment: .leading, spacing: Theme.space8) {
                                Text(block.title)
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.slate)
                                    .accessibilityAddTraits(.isHeader)
                                GroupedRows {
                                    ForEach(block.phrases, id: \.self) { phrase in
                                        Row(label: "\u{201C}\(phrase)\u{201D}", height: 48)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, Theme.space8)
                }
                .scrollIndicators(.hidden)
                // Room for the grabber and title above; the rows scroll under them.
                .frame(maxHeight: max(160, proxy.size.height * 0.62))
            }
        }
    }

    private var blocks: [Block] {
        let herePhrases = session.helpFrom == .cook ? CookPhrases.now(session) : session.helpPhrases
        let here = Block(id: "here", title: "Right now", phrases: herePhrases)
        return [here] + HelpGroup.ordered(for: session.helpFrom).map {
            Block(id: $0.rawValue, title: $0.title, phrases: $0.phrases)
        }
    }
}
