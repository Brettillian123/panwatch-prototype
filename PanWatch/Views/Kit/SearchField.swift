import SwiftUI

/// A search box: 48 tall, radius 14, ink 7 %, a magnifier, Body slate placeholder, and a
/// microphone glyph trailing. The glyph shows whether the app is listening and, tapped, runs
/// `onMicrophone` (turning listening off or on); with no action it is only a picture.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var listening = true
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
            if let onMicrophone {
                Button(action: onMicrophone) {
                    Image(systemName: listening ? "mic" : "mic.slash")
                        .foregroundStyle(Theme.slate)
                        .frame(width: Theme.minTarget, height: Theme.minTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(listening ? "Listening" : "Not listening")
                .accessibilityHint(listening ? "Stops listening" : "Starts listening")
            } else {
                Image(systemName: "mic")
                    .foregroundStyle(Theme.slate)
                    .frame(width: Theme.minTarget, height: Theme.minTarget)
                    .accessibilityHidden(true)
            }
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
