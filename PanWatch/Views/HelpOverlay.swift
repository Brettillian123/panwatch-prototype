import SwiftUI

/// "What can I say": the whole grammar in three columns at 28 pt. First, in Copper, the
/// phrases that work where the cook asked, which the app reads aloud (the first four);
/// then every group, the ones about that screen first. Closes on "done", Done, or by
/// itself after 30 seconds.
struct HelpOverlay: View {
    let session: CookSession

    /// A heading and its phrases; `here` marks the block that works on the screen asked from.
    private struct Block: Identifiable {
        let id: String
        let title: String
        let phrases: [String]
        var here = false
    }

    var body: some View {
        MenuScreen(session: session, title: "What you can say") {
            ScrollView {
                HStack(alignment: .top, spacing: Theme.gap * 2) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(alignment: .leading, spacing: Theme.gap * 2) {
                            ForEach(column) { block in
                                blockView(block)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
    }

    private var blocks: [Block] {
        let here = Block(id: "here", title: "Here", phrases: session.helpPhrases, here: true)
        return [here] + HelpGroup.ordered(for: session.helpFrom).map {
            Block(id: $0.rawValue, title: $0.title, phrases: $0.phrases)
        }
    }

    /// The blocks in reading order, down the first column and on into the next, each column
    /// holding about a third of the lines.
    private var columns: [[Block]] {
        let blocks = self.blocks
        let lines = blocks.reduce(0) { $0 + $1.phrases.count + 1 }
        let perColumn = (lines + 2) / 3
        var columns: [[Block]] = [[]]
        var filled = 0
        for block in blocks {
            let size = block.phrases.count + 1
            if filled > 0, filled + size > perColumn, columns.count < 3 {
                columns.append([])
                filled = 0
            }
            columns[columns.count - 1].append(block)
            filled += size
        }
        return columns
    }

    private func blockView(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text(block.title)
                .font(Theme.detail)
                .foregroundStyle(Theme.ash)
                .accessibilityAddTraits(.isHeader)
            ForEach(block.phrases, id: \.self) { phrase in
                Text(phrase)
                    .font(Theme.control)
                    .foregroundStyle(block.here ? Theme.copper : Theme.flour)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
