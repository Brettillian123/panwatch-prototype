import SwiftUI

/// The make-a-voice sheet over the voices. For now a titled placeholder; the Voices piece
/// fills it in. `RootView` draws it over `VoicesScreen` while the screen is `.makeVoice`.
struct MakeVoiceSheet: View {
    let session: CookSession

    var body: some View {
        BottomSheet(title: "Make a voice", close: { session.closeMenu() }) {
            Text("Blend two voices, or record your own.")
                .font(Theme.body)
                .foregroundStyle(Theme.slate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 120, alignment: .topLeading)
        }
    }
}

#Preview {
    MakeVoiceSheet(session: CookSession())
}
