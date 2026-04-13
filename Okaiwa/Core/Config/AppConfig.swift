// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Application configuration for different deployment environments.
///
/// Provides API base URLs, WebSocket endpoints, and feature flags
/// that vary between development, release candidate, and production.
struct AppConfig: Sendable {

    // MARK: - Environment

    enum Environment: String, Sendable {
        case dev
        case rec
        case prod
    }

    let environment: Environment
    let apiBaseURL: URL
    let webSocketURL: URL
    let identityServiceURL: URL
    let cdnBaseURL: URL

    // MARK: - Feature Flags

    let enableSealedSender: Bool
    let enableWallet: Bool
    let enableCalls: Bool
    let maxEphemeralTimerSeconds: Int
    let preKeyBatchSize: Int

    // MARK: - Singleton

    static let current: AppConfig = {
        #if DEBUG
        return .dev
        #else
        // Determine from bundle config or entitlements
        if let env = Bundle.main.infoDictionary?["OKAIWA_ENV"] as? String,
           env == "rec" {
            return .rec
        }
        return .prod
        #endif
    }()

    // MARK: - Predefined Configurations

    // Live identity service deployed behind okaiwa-api.globodai.group
    // — see okaiwa-server/identity. Same URL is used by the Android
    // twin via AppConfig.environment.apiBaseUrl. Points to the shared
    // dev/staging endpoint while the rec + prod environments are still
    // on their placeholder hostnames below.
    static let dev = AppConfig(
        environment: .dev,
        apiBaseURL: URL(string: "https://okaiwa-api.globodai.group/v1")!,
        webSocketURL: URL(string: "wss://okaiwa-api.globodai.group/v1/ws")!,
        identityServiceURL: URL(string: "https://okaiwa-api.globodai.group/v1")!,
        cdnBaseURL: URL(string: "https://okaiwa-api.globodai.group")!,
        enableSealedSender: true,
        enableWallet: true,
        enableCalls: false,
        maxEphemeralTimerSeconds: 604_800, // 7 days
        preKeyBatchSize: 100
    )

    static let rec = AppConfig(
        environment: .rec,
        apiBaseURL: URL(string: "https://api.rec.okaiwa.io/v1")!,
        webSocketURL: URL(string: "wss://ws.rec.okaiwa.io")!,
        identityServiceURL: URL(string: "https://identity.rec.okaiwa.io/v1")!,
        cdnBaseURL: URL(string: "https://cdn.rec.okaiwa.io")!,
        enableSealedSender: true,
        enableWallet: true,
        enableCalls: true,
        maxEphemeralTimerSeconds: 604_800,
        preKeyBatchSize: 100
    )

    static let prod = AppConfig(
        environment: .prod,
        apiBaseURL: URL(string: "https://api.okaiwa.io/v1")!,
        webSocketURL: URL(string: "wss://ws.okaiwa.io")!,
        identityServiceURL: URL(string: "https://identity.okaiwa.io/v1")!,
        cdnBaseURL: URL(string: "https://cdn.okaiwa.io")!,
        enableSealedSender: true,
        enableWallet: true,
        enableCalls: true,
        maxEphemeralTimerSeconds: 604_800,
        preKeyBatchSize: 100
    )
}

// MARK: - Convenience

extension AppConfig {

    /// Full URL for a given API path.
    func apiURL(path: String) -> URL {
        apiBaseURL.appendingPathComponent(path)
    }

    /// CDN URL for attachment retrieval.
    func cdnURL(attachmentId: String) -> URL {
        cdnBaseURL.appendingPathComponent("attachments/\(attachmentId)")
    }

    /// Whether the current environment is a debug/development build.
    var isDebug: Bool {
        environment == .dev
    }
}
