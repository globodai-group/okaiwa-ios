// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI
import UIKit
import os

/// Main entry point for the Okaiwa application.
///
/// Responsibilities:
/// - Bootstrap dependency injection container
/// - Enable screen security (screenshot prevention, app-switcher masking)
/// - Register for remote push notifications
@main
struct OkaiwaApp: App {

    // MARK: - Properties

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container: DependencyContainer
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "App")

    // MARK: - Initialization

    init() {
        container = DependencyContainer.shared
        container.bootstrap()
        configureAppearance()
        logger.info("Okaiwa initialized — environment: \(AppConfig.current.environment.rawValue)")
    }

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(container.authViewModel)
                .environment(container.router)
                .onAppear {
                    ScreenSecurity.enable()
                    registerForPushNotifications()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    // MARK: - Private

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error {
                logger.error("Push authorization failed: \(error.localizedDescription)")
                return
            }
            guard granted else {
                logger.info("Push authorization denied by user")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            logger.info("Push authorization granted")
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            logger.debug("App became active")
            ScreenSecurity.removeAppSwitcherMask()
        case .inactive:
            logger.debug("App became inactive")
            ScreenSecurity.applyAppSwitcherMask()
        case .background:
            logger.debug("App entered background")
            ScreenSecurity.applyAppSwitcherMask()
        @unknown default:
            break
        }
    }
}
