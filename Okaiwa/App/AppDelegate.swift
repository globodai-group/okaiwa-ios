// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import UIKit
import UserNotifications
import os

/// Application delegate for handling push notifications and lifecycle events.
///
/// Manages:
/// - Device token registration with the Okaiwa server
/// - Silent push notifications (`content-available: 1`) to trigger WebSocket message fetch
/// - Foreground notification presentation
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "AppDelegate")

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        logger.info("AppDelegate — didFinishLaunchingWithOptions")
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("APNs device token registered: \(tokenString.prefix(8))...")

        Task {
            await registerDeviceToken(tokenString)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }

    /// Handle silent push notifications (content-available: 1).
    /// Triggers a WebSocket reconnect and message fetch.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.info("Silent push received")

        guard let action = userInfo["action"] as? String else {
            completionHandler(.noData)
            return
        }

        Task {
            do {
                switch action {
                case "new_message":
                    try await fetchPendingMessages()
                    completionHandler(.newData)

                case "key_rotation":
                    try await handleKeyRotation()
                    completionHandler(.newData)

                case "session_invalidated":
                    try await handleSessionInvalidation()
                    completionHandler(.newData)

                default:
                    logger.warning("Unknown silent push action: \(action)")
                    completionHandler(.noData)
                }
            } catch {
                logger.error("Silent push handler failed: \(error.localizedDescription)")
                completionHandler(.failed)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Present notifications while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and sound for messages from other conversations
        let userInfo = notification.request.content.userInfo
        let conversationId = userInfo["conversationId"] as? String

        // If the user is currently viewing this conversation, suppress the banner
        if let conversationId, isViewingConversation(conversationId) {
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .sound, .badge])
        }
    }

    /// Handle notification tap — navigate to the relevant conversation or screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let conversationId = userInfo["conversationId"] as? String {
            logger.info("Notification tapped — navigating to conversation: \(conversationId.prefix(8))")
            navigateToConversation(conversationId)
        }

        completionHandler()
    }

    // MARK: - Private

    private func registerDeviceToken(_ token: String) async {
        // TODO: Send device token to Okaiwa server for push delivery
        logger.debug("Device token queued for server registration")
    }

    private func fetchPendingMessages() async throws {
        // TODO: Reconnect WebSocket and pull pending messages
        logger.debug("Fetching pending messages via WebSocket")
    }

    private func handleKeyRotation() async throws {
        // TODO: Rotate pre-key bundles when server signals exhaustion
        logger.debug("Handling key rotation signal")
    }

    private func handleSessionInvalidation() async throws {
        // TODO: Reset session and re-negotiate with contact
        logger.debug("Handling session invalidation")
    }

    private func isViewingConversation(_ conversationId: String) -> Bool {
        // TODO: Check current navigation state against conversationId
        return false
    }

    private func navigateToConversation(_ conversationId: String) {
        // TODO: Deep-link navigation to conversation
        logger.debug("Navigate to conversation: \(conversationId.prefix(8))")
    }
}
