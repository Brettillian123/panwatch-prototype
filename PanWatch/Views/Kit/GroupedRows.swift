import SwiftUI

/// Rows in one white card with dividers between them, inset 16 from both edges. Rows that
/// start with a round button pass `dividerLeading` so the divider starts at the words. Pass
/// `Row`s, or any view at least 60 tall.
struct GroupedRows<Content: View>: View {
    var dividerLeading: CGFloat = Theme.space16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    row
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                            .padding(.leading, dividerLeading)
                            .padding(.trailing, Theme.space16)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .cardShadow()
    }
}

/// One row: a Body ink label and a Body slate value, 60 tall (64 for voice rows). With an
/// action it is one button and shows a chevron when `chevron` is set.
struct Row<Leading: View, Trailing: View>: View {
    let label: String
    var detail: String? = nil
    var value: String? = nil
    var height: CGFloat = 60
    var chevron = false
    var action: (() -> Void)? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(RowPressStyle())
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: Theme.space12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.body).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.slate)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: Theme.space8)
            if let value {
                Text(value).font(Theme.body).monospacedDigit().foregroundStyle(Theme.slate)
                    .multilineTextAlignment(.trailing)
            }
            trailing
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.slate)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.space16)
        .padding(.vertical, Theme.space8)
        .frame(minHeight: height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension Row where Leading == EmptyView, Trailing == EmptyView {
    init(label: String, detail: String? = nil, value: String? = nil, height: CGFloat = 60,
         chevron: Bool = false, action: (() -> Void)? = nil) {
        self.init(label: label, detail: detail, value: value, height: height, chevron: chevron, action: action,
                  leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension Row where Trailing == EmptyView {
    init(label: String, detail: String? = nil, value: String? = nil, height: CGFloat = 60,
         chevron: Bool = false, action: (() -> Void)? = nil, @ViewBuilder leading: () -> Leading) {
        self.init(label: label, detail: detail, value: value, height: height, chevron: chevron, action: action,
                  leading: leading, trailing: { EmptyView() })
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.fill : Color.clear)
    }
}

#Preview {
    GroupedRows {
        Row(label: "Pasta", value: "1 pound")
        Row(label: "Salt", value: "1 tablespoon")
        Row(label: "Ava", detail: "American · Warm, steady", height: 64, chevron: true, action: {})
    }
    .padding(20)
    .background(Theme.ground)
}
