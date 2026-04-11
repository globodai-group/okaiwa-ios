// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Authenticated user entity.
///
/// Represents the locally registered user with their cryptographic identity.
/// The phone number is never stored in plaintext — only the PBKDF2 hash is persisted.
struct User: Identifiable, Codable, Sendable, Equatable {

    /// Server-assigned unique identifier (UUID v4).
    let id: String

    /// PBKDF2-SHA256 hash of the phone number.
    /// Used for contact discovery without revealing the actual number.
    let phoneNumberHash: String

    /// User-chosen display name (unique, 3-32 characters).
    let username: String

    /// X25519 identity public key for the Signal Protocol.
    /// Generated locally, never leaves the device as a private key.
    let identityPublicKey: Data

    /// Current signed pre-key public component.
    /// Rotated periodically (every 48 hours or on demand).
    let signedPreKeyPublic: Data

    /// Signed pre-key identifier (monotonically increasing).
    let signedPreKeyId: UInt32

    /// Registration timestamp.
    let createdAt: Date

    /// Last time pre-keys were uploaded to the server.
    var lastPreKeyUpload: Date?

    /// Device ID for multi-device support.
    let deviceId: UInt32

    // MARK: - Computed

    /// Fingerprint derived from the identity public key.
    /// Displayed to users for out-of-band verification.
    var fingerprint: String {
        identityPublicKey
            .map { String(format: "%02x", $0) }
            .joined()
            .uppercased()
            .chunked(size: 4)
            .joined(separator: " ")
    }

    /// Whether pre-keys should be refreshed.
    var needsPreKeyRefresh: Bool {
        guard let lastUpload = lastPreKeyUpload else { return true }
        return Date().timeIntervalSince(lastUpload) > 48 * 3600 // 48 hours
    }
}

// MARK: - String Chunking

private extension String {
    func chunked(size: Int) -> [String] {
        stride(from: 0, to: count, by: size).map { offset in
            let start = index(startIndex, offsetBy: offset)
            let end = index(start, offsetBy: min(size, count - offset))
            return String(self[start..<end])
        }
    }
}
