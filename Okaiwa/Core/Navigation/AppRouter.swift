// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI
import os

// MARK: - Route

/// All navigable destinations in the app.
enum Route: Hashable {
    // Auth
    case login
    case verifyCode(phoneHash: String)
    case chooseUsername

    // Chat
    case conversationList
    case chat(conversationId: String)
    case newMessage
    case conversationDetails(conversationId: String)

    // Contacts
    case contactList
    case contactDetails(contactId: String)
    case verifyIdentity(contactId: String)

    // Wallet
    case walletHome
    case sendCrypto(chain: String)
    case receiveCrypto(chain: String)
    case transactionDetails(hash: String)

    // Calls
    case callHistory
    case activeCall(callId: String)

    // Settings
    case settings
    case securitySettings
    case privacySettings
    case notificationSettings
    case linkedDevices
    case about

    // Profile
    case profile
    case editProfile
}

// MARK: - App Router

/// Centralized navigation controller using `NavigationPath`.
///
/// Manages the navigation stack for the entire app. Injected as an
/// environment object so any view can trigger navigation.
@Observable
final class AppRouter {

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "Router")

    /// The navigation path backing `NavigationStack`.
    var path = NavigationPath()

    /// Modal sheet currently presented, if any.
    var presentedSheet: Route?

    /// Full-screen cover currently presented, if any.
    var presentedFullScreenCover: Route?

    // MARK: - Navigation

    /// Push a route onto the navigation stack.
    func navigate(to route: Route) {
        logger.debug("Navigate to: \(String(describing: route))")
        path.append(route)
    }

    /// Pop the top route from the navigation stack.
    func pop() {
        guard !path.isEmpty else { return }
        logger.debug("Pop navigation")
        path.removeLast()
    }

    /// Pop to the root of the navigation stack.
    func popToRoot() {
        logger.debug("Pop to root")
        path = NavigationPath()
    }

    /// Present a route as a modal sheet.
    func presentSheet(_ route: Route) {
        logger.debug("Present sheet: \(String(describing: route))")
        presentedSheet = route
    }

    /// Present a route as a full-screen cover.
    func presentFullScreen(_ route: Route) {
        logger.debug("Present full-screen: \(String(describing: route))")
        presentedFullScreenCover = route
    }

    /// Dismiss the current sheet or full-screen cover.
    func dismiss() {
        presentedSheet = nil
        presentedFullScreenCover = nil
    }

    /// Deep-link into a conversation (e.g., from a push notification).
    func deepLinkToConversation(_ conversationId: String) {
        popToRoot()
        // Small delay so the root settles before pushing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.navigate(to: .chat(conversationId: conversationId))
        }
    }

    /// Deep-link into a transaction detail.
    func deepLinkToTransaction(_ txHash: String) {
        popToRoot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.navigate(to: .transactionDetails(hash: txHash))
        }
    }
}

// MARK: - View Modifier for Route Destinations

extension View {

    /// Attach navigation destinations for all known routes.
    func withOkaiwaDestinations() -> some View {
        self.navigationDestination(for: Route.self) { route in
            switch route {
            case .chat(let conversationId):
                ChatView(conversationId: conversationId)

            case .conversationList:
                ConversationListView()

            case .walletHome:
                WalletView()

            case .settings:
                SettingsView()

            default:
                // Placeholder for routes not yet implemented
                Text("Screen: \(String(describing: route))")
                    .navigationTitle("Coming Soon")
            }
        }
    }
}
