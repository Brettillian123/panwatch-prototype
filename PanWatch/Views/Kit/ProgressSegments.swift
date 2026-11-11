import SwiftUI

/// How far through a recipe: `total` short bars, the first `done` beet, the rest ink 7 %.
/// 6 tall with a 4 gap; it fills the width it is given. Past ten steps the bars would be
/// slivers, so it is one continuous bar of the same height and colors.
struct ProgressSegments: View {
    let done: Int
    let total: Int
    var height: CGFloat = 6

    /// The most steps still drawn as separate bars.
    static let maxSegments = 10

    var body: some View {
        Group {
            if total > Self.maxSegments {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous).fill(Theme.divider)
                        Capsule(style: .continuous).fill(Theme.beet)
                            .frame(width: geometry.size.width * CGFloat(min(max(done, 0), total)) / CGFloat(total))
                    }
                }
                .frame(height: height)
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<max(total, 1), id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index < done ? Theme.beet : Theme.divider)
                            .frame(height: height)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(min(done, total)) of \(total)")
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressSegments(done: 3, total: 5)
        ProgressSegments(done: 2, total: 5).frame(width: 120)
    }
    .padding(20)
    .background(Theme.ground)
}
