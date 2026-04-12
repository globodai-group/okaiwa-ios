import SwiftUI

/// Placeholder views for the three main tabs where the real SwiftUI
/// screens aren't checked in yet. They match the Android tab surfaces
/// visually (dark canvas, centered lime label) so the nav shell can be
/// tested before the real views land.
///
/// Remove each placeholder as its full implementation ships:
///   - ChatsTabPlaceholder    → ConversationListView
///   - WalletTabPlaceholder   → WalletView
///   - SettingsTabPlaceholder → SettingsView

struct ChatsTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(title: "Échanges", subtitle: "Liste des conversations")
    }
}

struct WalletTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(title: "Wallet", subtitle: "Balances multi-chaînes")
    }
}

struct SettingsTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(title: "Paramètres", subtitle: "Sécurité, sauvegarde, confidentialité")
    }
}

private struct TabPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.lime)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(OkaiwaColors.muted)
            }
        }
    }
}
