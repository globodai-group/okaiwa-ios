// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// A contact known to the user.
///
/// Contacts are discovered via hashed phone number lookup against the
/// identity service. The actual phone number is never sent to the server.
struct Contact: Identifiable, Codable, Sendable, Equatable {

    /// Server-assigned unique identifier.
    let id: String

    /// The contact's username on Okaiwa.
    let username: String

    /// Display name chosen by the contact.
    var displayName: String?

    /// PBKDF2-SHA256 hash of the contact's phone number.
    /// Used for discovery and deduplication.
    let phoneHash: String

    /// The contact's X25519 identity public key.
    /// Used for Signal Protocol session establishment and safety number computation.
    let publicIdentityKey: Data

    /// Whether the user has verified this contact's safety number
    /// (e.g., by scanning a QR code in person).
    var safetyNumberVerified: Bool

    /// Date when the safety number was last verified.
    var safetyNumberVerifiedAt: Date?

    /// The contact's public wallet addresses (shared voluntarily).
    var walletAddresses: [WalletAddress]

    /// Avatar attachment ID on CDN.
    var avatarAttachmentId: String?

    /// Whether this contact is blocked.
    var isBlocked: Bool

    /// When the contact was added.
    let addedAt: Date

    /// Last seen online (if the contact allows this to be shared).
    var lastSeenAt: Date?

    // MARK: - Nested Types

    /// A wallet address shared by the contact.
    struct WalletAddress: Codable, Sendable, Equatable, Identifiable {
        var id: String { "\(chain.rawValue):\(address)" }
        let chain: Wallet.Chain
        let address: String
        /// Whether this address has been verified on-chain.
        let isVerified: Bool
    }
}

// MARK: - Convenience

extension Contact {

    /// The name to display (display name, falling back to username).
    var resolvedDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return username
    }

    /// Initials for avatar placeholder.
    var initials: String {
        let name = resolvedDisplayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Fingerprint derived from the identity public key (for display).
    var fingerprint: String {
        publicIdentityKey
            .map { String(format: "%02x", $0) }
            .joined()
            .uppercased()
            .chunked(size: 5)
            .joined(separator: " ")
    }

    /// Wallet address for a specific chain, if shared.
    func walletAddress(for chain: Wallet.Chain) -> String? {
        walletAddresses.first { $0.chain == chain }?.address
    }

    /// Whether the contact has shared any wallet addresses.
    var hasWalletAddresses: Bool {
        !walletAddresses.isEmpty
    }
}

// MARK: - Private Helpers

private extension String {
    func chunked(size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: min(size, count - offset))
            return String(self[start..<end])
        }
    }
}
