import SwiftUI

/// Cook mode, landscape only. For now the old cook screen; the Cook piece rebuilds it here.
struct CookScreen: View {
    let session: CookSession

    var body: some View {
        ContentView(session: session)
    }
}

#Preview(traits: .landscapeLeft) {
    CookScreen(session: CookSession())
}
