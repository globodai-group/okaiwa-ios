// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Security score assessment for the user's device and account.
///
/// Evaluates 7 security criteria and computes an overall percentage.
/// Displayed in Settings as a ring chart with actionable recommendations.
struct SecurityScore: Sendable, Equatable {

    // MARK: - Criteria

    /// Whether the device has a passcode/biometric lock enabled.
    let devicePasscodeEnabled: Bool

    /// Whether biometric authentication (Face ID / Touch ID) is enabled for Okaiwa.
    let biometricEnabled: Bool

    /// Whether the user has verified at least one contact's safety number.
    let safetyNumberVerified: Bool

    /// Whether disappearing messages are enabled for at least one conversation.
    let ephemeralMessagesEnabled: Bool

    /// Whether the user's pre-key bundle is up to date on the server.
    let preKeysUpToDate: Bool

    /// Whether screen security (screenshot prevention) is active.
    let screenSecurityEnabled: Bool

    /// Whether the app is on the latest version.
    let appUpToDate: Bool

    // MARK: - Computed

    /// Array of all criteria with their status.
    var criteria: [Criterion] {
        [
            Criterion(
                name: "Device Passcode",
                description: "Protect your device with a passcode or biometric lock.",
                isPassed: devicePasscodeEnabled,
                icon: "lock.fill",
                priority: .critical
            ),
            Criterion(
                name: "Biometric Authentication",
                description: "Use Face ID or Touch ID to unlock Okaiwa.",
                isPassed: biometricEnabled,
                icon: "faceid",
                priority: .high
            ),
            Criterion(
                name: "Identity Verification",
                description: "Verify at least one contact's safety number in person.",
                isPassed: safetyNumberVerified,
                icon: "checkmark.shield.fill",
                priority: .high
            ),
            Criterion(
                name: "Disappearing Messages",
                description: "Enable ephemeral messages to reduce your data footprint.",
                isPassed: ephemeralMessagesEnabled,
                icon: "timer",
                priority: .medium
            ),
            Criterion(
                name: "Pre-Key Freshness",
                description: "Keep your encryption keys rotated and up to date.",
                isPassed: preKeysUpToDate,
                icon: "key.fill",
                priority: .high
            ),
            Criterion(
                name: "Screen Security",
                description: "Prevent screenshots and app-switcher previews.",
                isPassed: screenSecurityEnabled,
                icon: "eye.slash.fill",
                priority: .medium
            ),
            Criterion(
                name: "App Up to Date",
                description: "Run the latest version for security patches.",
                isPassed: appUpToDate,
                icon: "arrow.triangle.2.circlepath",
                priority: .medium
            ),
        ]
    }

    /// Number of criteria that pass.
    var passedCount: Int {
        criteria.filter(\.isPassed).count
    }

    /// Total number of criteria.
    var totalCount: Int {
        criteria.count
    }

    /// Overall security score as a percentage (0-100).
    var percentage: Int {
        guard totalCount > 0 else { return 0 }

        // Weighted scoring: critical = 2x, high = 1.5x, medium = 1x
        let totalWeight = criteria.reduce(0.0) { $0 + $1.priority.weight }
        let passedWeight = criteria.filter(\.isPassed).reduce(0.0) { $0 + $1.priority.weight }

        return Int((passedWeight / totalWeight) * 100)
    }

    /// Human-readable grade based on percentage.
    var grade: Grade {
        switch percentage {
        case 90...100: return .excellent
        case 70..<90: return .good
        case 50..<70: return .fair
        default: return .poor
        }
    }

    /// Actionable recommendations for failed criteria.
    var recommendations: [Criterion] {
        criteria.filter { !$0.isPassed }
            .sorted { $0.priority.weight > $1.priority.weight }
    }

    // MARK: - Nested Types

    struct Criterion: Sendable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let description: String
        let isPassed: Bool
        let icon: String
        let priority: Priority
    }

    enum Priority: Sendable, Equatable {
        case critical
        case high
        case medium

        var weight: Double {
            switch self {
            case .critical: return 2.0
            case .high: return 1.5
            case .medium: return 1.0
            }
        }

        var label: String {
            switch self {
            case .critical: return "Critical"
            case .high: return "Important"
            case .medium: return "Recommended"
            }
        }
    }

    enum Grade: Sendable {
        case excellent
        case good
        case fair
        case poor

        var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Needs Attention"
            }
        }

        var emoji: String {
            switch self {
            case .excellent: return "A+"
            case .good: return "B"
            case .fair: return "C"
            case .poor: return "D"
            }
        }
    }
}

// MARK: - Factory

extension SecurityScore {

    /// Evaluate the current security posture.
    ///
    /// In production, each criterion queries real system state.
    static func evaluate(
        devicePasscodeEnabled: Bool = true,
        biometricEnabled: Bool = false,
        safetyNumberVerified: Bool = false,
        ephemeralMessagesEnabled: Bool = false,
        preKeysUpToDate: Bool = true,
        screenSecurityEnabled: Bool = true,
        appUpToDate: Bool = true
    ) -> SecurityScore {
        SecurityScore(
            devicePasscodeEnabled: devicePasscodeEnabled,
            biometricEnabled: biometricEnabled,
            safetyNumberVerified: safetyNumberVerified,
            ephemeralMessagesEnabled: ephemeralMessagesEnabled,
            preKeysUpToDate: preKeysUpToDate,
            screenSecurityEnabled: screenSecurityEnabled,
            appUpToDate: appUpToDate
        )
    }
}
