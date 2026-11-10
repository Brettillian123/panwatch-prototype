import SwiftUI

/// The profile, which holds what used to be the settings. For now the old settings
/// screen; the Profile piece rebuilds it here.
struct ProfileScreen: View {
    let session: CookSession

    var body: some View {
        SettingsScreen(session: session)
            .padding(.horizontal, Theme.margin)
            .screenColumn()
    }
}

#Preview {
    ProfileScreen(session: CookSession())
}
