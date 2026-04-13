// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI
// Imports required for `L10n` (localization helper) + feature Views
// referenced below. The host target links against both libraries in
// the Xcode project; keep these two lines in sync with that config.
import OkaiwaCore
import OkaiwaFeatures

/// Root view that switches between authentication and main app flows.
///
/// Observes the `AuthViewModel` to determine whether the user is authenticated.
/// Shows `LoginView` for unauthenticated users, or `MainTabView` for authenticated users.
struct ContentView: View {

    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch authViewModel.state {
            case .idle, .enteringPhone, .verifyingCode, .choosingUsername:
                LoginView()
                    .transition(.opacity.combined(with: .move(edge: .leading)))

            case .authenticated:
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

            case .error(let message):
                ErrorRecoveryView(message: message) {
                    authViewModel.resetToIdle()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authViewModel.state)
    }
}

// MARK: - Main Tab View

/// Primary navigation after authentication.
/// Tab bar with: Chats, Contacts, Wallet, Calls, Settings.
struct MainTabView: View {

    @State private var selectedTab: AppTab = .chats

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ConversationListView(
                    onNavigateToChat: { _ in },
                    onNavigateToContacts: {}
                )
            }
            .tabItem {
                Label(Text(L10n.string("tab_chats")), systemImage: "message.fill")
            }
            .tag(AppTab.chats)

            NavigationStack {
                // Placeholder for ContactsListView — the raw text is
                // left verbatim because this screen is swapped out
                // before the screen is reachable by end users.
                Text(verbatim: "Contacts")
                    .navigationTitle(Text(verbatim: "Contacts"))
            }
            .tabItem {
                Label(Text(verbatim: "Contacts"), systemImage: "person.2.fill")
            }
            .tag(AppTab.contacts)

            NavigationStack {
                WalletView()
            }
            .tabItem {
                Label(Text(L10n.string("tab_wallet")), systemImage: "creditcard.fill")
            }
            .tag(AppTab.wallet)

            NavigationStack {
                Text(verbatim: "Calls") // Placeholder for CallsListView
                    .navigationTitle(Text(verbatim: "Calls"))
            }
            .tabItem {
                Label(Text(verbatim: "Calls"), systemImage: "phone.fill")
            }
            .tag(AppTab.calls)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(Text(L10n.string("tab_settings")), systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(OkaiwaTheme.Colors.primaryFallback)
        // Kick the relay poller + pre-key warmup as soon as the user
        // lands on the authenticated surface. Mirrors the Android
        // `MainActivity.onResume → pollingService.start()` +
        // `RemoteAuthRepository.ensurePreKeysUploaded()` fan-out:
        //   - `ensurePreKeysUploaded` is idempotent (gated by the
        //     `preKeysUploaded` flag in the Keychain-backed snapshot)
        //     and re-pushes the kyber for pre-commit users without a
        //     re-run of /auth/verify (review P0 #5 mirror).
        //   - `MessagePollingService.start()` launches the 5s poll
        //     loop; `.onDisappear` stops it so we don't drain battery
        //     on the lock screen / in app-switcher.
        .task {
            await DependencyContainer.shared.identityAuthService().ensurePreKeysUploaded()
            MessagePollingService.shared.start()
        }
        .onDisappear {
            MessagePollingService.shared.stop()
        }
    }
}

// MARK: - Supporting Types

enum AppTab: Hashable {
    case chats
    case contacts
    case wallet
    case calls
    case settings
}

// MARK: - Error Recovery View

struct ErrorRecoveryView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: OkaiwaTheme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(OkaiwaTheme.Colors.destructive)

            Text(L10n.string("error_recovery_title"))
                .font(OkaiwaTheme.Typography.headline)

            Text(message)
                .font(OkaiwaTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OkaiwaTheme.Spacing.xl)

            Button(L10n.string("error_recovery_retry"), action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(OkaiwaTheme.Colors.primaryFallback)
        }
    }
}
