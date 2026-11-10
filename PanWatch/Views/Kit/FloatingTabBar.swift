import SwiftUI

/// The floating tab bar: a white capsule 64 tall with the floating shadow, four tabs of an
/// SF Symbol over a Caption label. The selected tab is beet on a blush capsule.
struct FloatingTabBar: View {
    let selected: AppTab?
    let choose: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = tab == selected
                Button { choose(tab) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(Theme.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? Theme.beet : Theme.slate)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if isSelected { Capsule(style: .continuous).fill(Theme.blush) }
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(6)
        .frame(minHeight: 64)
        .background(Theme.card, in: Capsule(style: .continuous))
        .floatingShadow()
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, Theme.space8)
        .frame(maxWidth: Theme.columnMax)
    }
}

#Preview {
    VStack {
        Spacer()
        FloatingTabBar(selected: .recipes) { _ in }
    }
    .background(Theme.ground)
}
