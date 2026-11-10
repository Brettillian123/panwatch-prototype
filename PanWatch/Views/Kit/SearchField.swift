import SwiftUI

/// A search box: 48 tall, radius 14, ink 7 %, a magnifier, Body slate placeholder, and a
/// microphone glyph trailing that runs `onMicrophone` when tapped.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var onMicrophone: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.slate)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.slate))
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.slate)
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Button { onMicrophone?() } label: {
                Image(systemName: "mic")
                    .foregroundStyle(Theme.slate)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search by voice")
        }
        .font(Theme.body)
        .padding(.leading, 14)
        .frame(minHeight: 48)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.radiusField, style: .continuous))
    }
}

#Preview {
    struct Demo: View {
        @State var text = ""
        var body: some View {
            SearchField(placeholder: "Search recipes", text: $text)
                .padding(20)
                .background(Theme.ground)
        }
    }
    return Demo()
}
