import SwiftUI

/// Home: the recipes. For now the old recipe menu; the Home piece rebuilds it here.
struct HomeScreen: View {
    let session: CookSession

    var body: some View {
        RecipePicker(session: session)
            .padding(.horizontal, Theme.margin)
            .screenColumn()
    }
}

#Preview {
    HomeScreen(session: CookSession())
}
