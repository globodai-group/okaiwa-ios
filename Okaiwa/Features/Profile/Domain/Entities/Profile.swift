// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// User profile — public-facing information shared with contacts.
///
/// Profile data is end-to-end encrypted when stored on the server.
/// Other users can only see fields that match the visibility settings.
struct Profile: Codable, Sendable, Equatable {

    /// The user's unique username.
    let username: String

    /// Display name shown to contacts.
    var displayName: String

    /// Short bio / status message.
    var bio: String

    /// Avatar attachment ID on CDN (encrypted).
    var avatarAttachmentId: String?

    /// Wallet addresses the user chooses to share publicly.
    var walletAddresses: [SharedWalletAddress]

    /// Visibility settings for profile fields.
    var visibility: Visibility

    /// When the profile was last updated.
    var updatedAt: Date

    // MARK: - Nested Types

    /// A wallet address explicitly shared in the profile.
    struct SharedWalletAddress: Codable, Sendable, Equatable, Identifiable {
        var id: String { "\(chain.rawValue):\(address)" }
        let chain: Wallet.Chain
        let address: String
        /// User-assigned label (e.g., "Main", "Business").
        var label: String?
    }

    /// Controls who can see each profile field.
    struct Visibility: Codable, Sendable, Equatable {
        /// Who can see the user's display name.
        var displayName: VisibilityLevel

        /// Who can see the bio.
        var bio: VisibilityLevel

        /// Who can see the avatar.
        var avatar: VisibilityLevel

        /// Who can see wallet addresses.
        var walletAddresses: VisibilityLevel

        /// Who can see last-seen timestamp.
        var lastSeen: VisibilityLevel

        /// Who can see read receipts.
        var readReceipts: VisibilityLevel

        /// Default visibility settings.
        static let `default` = Visibility(
            displayName: .contacts,
            bio: .contacts,
            avatar: .contacts,
            walletAddresses: .nobody,
            lastSeen: .contacts,
            readReceipts: .contacts
        )
    }

    /// Visibility level for a profile field.
    enum VisibilityLevel: String, Codable, Sendable, CaseIterable {
        /// Visible to everyone.
        case everyone
        /// Visible only to contacts.
        case contacts
        /// Visible to nobody.
        case nobody

        var displayName: String {
            switch self {
            case .everyone: return "Everyone"
            case .contacts: return "Contacts Only"
            case .nobody: return "Nobody"
            }
        }
    }
}

// MARK: - Convenience

extension Profile {

    /// Whether the profile has a bio.
    var hasBio: Bool {
        !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether the profile has an avatar.
    var hasAvatar: Bool {
        avatarAttachmentId != nil
    }

    /// Whether any wallet addresses are shared.
    var hasSharedWallets: Bool {
        !walletAddresses.isEmpty
    }

    /// Initials for avatar placeholder.
    var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }

    /// Create an empty profile for a new user.
    static func empty(username: String) -> Profile {
        Profile(
            username: username,
            displayName: username,
            bio: "",
            avatarAttachmentId: nil,
            walletAddresses: [],
            visibility: .default,
            updatedAt: Date()
        )
    }
}
