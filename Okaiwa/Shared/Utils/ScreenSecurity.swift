// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import UIKit
import os

/// Screen security utilities to prevent unauthorized capture of sensitive content.
///
/// Provides three layers of protection:
/// 1. **Screenshot prevention** — Uses a `UITextField.isSecureTextEntry` overlay trick
///    to prevent iOS from capturing screen content in screenshots.
/// 2. **Screen recording detection** — Monitors `UIScreen.isCaptured` to detect
///    screen recording and overlay a privacy shield.
/// 3. **App switcher masking** — Covers the UI with a branded splash when
///    the app enters the background, preventing content exposure in the task switcher.
enum ScreenSecurity {

    private static let logger = Logger(subsystem: "io.okaiwa.app", category: "ScreenSecurity")
    private static var secureField: UITextField?
    private static var maskWindow: UIWindow?
    private static var recordingObserver: NSObjectProtocol?

    // MARK: - Enable / Disable

    /// Enable screenshot prevention on the key window.
    ///
    /// Uses the `UITextField.isSecureTextEntry` technique: a secure text field
    /// placed in the view hierarchy causes iOS to blank the screenshot output
    /// for the entire window.
    static func enable() {
        guard secureField == nil else { return }

        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  let window = windowScene.windows.first else {
                logger.warning("No window found — screenshot prevention not applied")
                return
            }

            let field = UITextField()
            field.isSecureTextEntry = true
            field.isUserInteractionEnabled = false
            field.translatesAutoresizingMaskIntoConstraints = false

            // The secure field must be in the view hierarchy but invisible
            window.addSubview(field)
            NSLayoutConstraint.activate([
                field.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                field.centerYAnchor.constraint(equalTo: window.centerYAnchor),
                field.widthAnchor.constraint(equalToConstant: 0),
                field.heightAnchor.constraint(equalToConstant: 0),
            ])

            secureField = field
            logger.info("Screenshot prevention enabled")

            // Start screen recording detection
            startRecordingDetection()
        }
    }

    /// Disable screenshot prevention.
    static func disable() {
        DispatchQueue.main.async {
            secureField?.removeFromSuperview()
            secureField = nil
            stopRecordingDetection()
            logger.info("Screenshot prevention disabled")
        }
    }

    // MARK: - App Switcher Masking

    /// Show a privacy mask over the UI (for app switcher / background).
    ///
    /// Creates a separate UIWindow at the alert level that covers the
    /// entire screen with the Okaiwa logo on a solid background.
    static func applyAppSwitcherMask() {
        DispatchQueue.main.async {
            guard maskWindow == nil else { return }

            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else {
                return
            }

            let mask = UIWindow(windowScene: windowScene)
            mask.windowLevel = .alert + 1
            mask.backgroundColor = UIColor.systemBackground

            let maskController = UIViewController()
            maskController.view.backgroundColor = UIColor.systemBackground

            // App icon / logo
            let imageView = UIImageView()
            imageView.image = UIImage(systemName: "shield.checkered")
            imageView.tintColor = UIColor(red: 0, green: 0.59, blue: 0.53, alpha: 1)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            maskController.view.addSubview(imageView)

            // App name
            let label = UILabel()
            label.text = "Okaiwa"
            label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
            label.textColor = UIColor.label
            label.translatesAutoresizingMaskIntoConstraints = false
            maskController.view.addSubview(label)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: maskController.view.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: maskController.view.centerYAnchor, constant: -30),
                imageView.widthAnchor.constraint(equalToConstant: 80),
                imageView.heightAnchor.constraint(equalToConstant: 80),
                label.centerXAnchor.constraint(equalTo: maskController.view.centerXAnchor),
                label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            ])

            mask.rootViewController = maskController
            mask.isHidden = false

            maskWindow = mask
            logger.debug("App switcher mask applied")
        }
    }

    /// Remove the app switcher privacy mask.
    static func removeAppSwitcherMask() {
        DispatchQueue.main.async {
            maskWindow?.isHidden = true
            maskWindow = nil
            logger.debug("App switcher mask removed")
        }
    }

    // MARK: - Screen Recording Detection

    /// Start monitoring for screen recording.
    private static func startRecordingDetection() {
        recordingObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let isCaptured = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .contains { $0.screen.isCaptured }

            if isCaptured {
                logger.warning("Screen recording detected")
                applyAppSwitcherMask()
            } else {
                logger.info("Screen recording stopped")
                removeAppSwitcherMask()
            }
        }

        // Check current state
        let isCaptured = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }

        if isCaptured {
            logger.warning("Screen recording active at launch")
            applyAppSwitcherMask()
        }
    }

    /// Stop monitoring for screen recording.
    private static func stopRecordingDetection() {
        if let observer = recordingObserver {
            NotificationCenter.default.removeObserver(observer)
            recordingObserver = nil
        }
    }
}
