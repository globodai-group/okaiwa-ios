// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

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
                ConversationListView()
            }
            .tabItem {
                Label("Chats", systemImage: "message.fill")
            }
            .tag(AppTab.chats)

            NavigationStack {
                Text("Contacts") // Placeholder for ContactsListView
                    .navigationTitle("Contacts")
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2.fill")
            }
            .tag(AppTab.contacts)

            NavigationStack {
                WalletView()
            }
            .tabItem {
                Label("Wallet", systemImage: "creditcard.fill")
            }
            .tag(AppTab.wallet)

            NavigationStack {
                Text("Calls") // Placeholder for CallsListView
                    .navigationTitle("Calls")
            }
            .tabItem {
                Label("Calls", systemImage: "phone.fill")
            }
            .tag(AppTab.calls)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
        }
        .tint(OkaiwaTheme.Colors.primaryFallback)
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

            Text("Something went wrong")
                .font(OkaiwaTheme.Typography.headline)

            Text(message)
                .font(OkaiwaTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OkaiwaTheme.Spacing.xl)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(OkaiwaTheme.Colors.primaryFallback)
        }
    }
}
