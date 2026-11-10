import SwiftUI

/// The voices. For now the old voice menu; the Voices piece rebuilds it here.
struct VoicesScreen: View {
    let session: CookSession

    var body: some View {
        VoicePicker(session: session)
            .padding(.horizontal, Theme.margin)
            .screenColumn()
    }
}

#Preview {
    VoicesScreen(session: CookSession())
}
