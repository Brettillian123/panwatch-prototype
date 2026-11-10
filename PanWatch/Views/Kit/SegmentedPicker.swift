import SwiftUI

/// Two or three choices in an ink 7 % capsule, 44 tall. The selected one is semibold ink on a
/// white capsule, the others regular slate.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    withAnimation(Theme.motion) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(selected ? Theme.bodyStrong : Theme.body)
                        .foregroundStyle(selected ? Theme.ink : Theme.slate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected {
                                Capsule(style: .continuous).fill(Theme.card).controlShadow()
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(minHeight: 44)
        .background(Theme.fill, in: Capsule(style: .continuous))
    }
}

#Preview {
    struct Demo: View {
        @State var tab = 0
        var body: some View {
            SegmentedPicker(options: [(value: 0, title: "Ingredients"), (value: 1, title: "Steps")], selection: $tab)
                .padding(20)
                .background(Theme.ground)
        }
    }
    return Demo()
}
