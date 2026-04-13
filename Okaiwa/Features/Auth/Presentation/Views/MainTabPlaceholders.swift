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
        TabPlaceholder(titleKey: "tab_chats", subtitleKey: "tab_chats_placeholder_subtitle")
    }
}

struct WalletTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(titleKey: "tab_wallet", subtitleKey: "tab_wallet_placeholder_subtitle")
    }
}

struct SettingsTabPlaceholder: View {
    var body: some View {
        TabPlaceholder(titleKey: "tab_settings", subtitleKey: "tab_settings_placeholder_subtitle")
    }
}

private struct TabPlaceholder: View {
    let titleKey: String
    let subtitleKey: String

    var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()
            VStack(spacing: 8) {
                Text(L10n.key(titleKey))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.lime)
                Text(L10n.key(subtitleKey))
                    .font(.system(size: 14))
                    .foregroundStyle(OkaiwaColors.muted)
            }
        }
    }
}
