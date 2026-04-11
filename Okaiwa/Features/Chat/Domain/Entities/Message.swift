// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// An encrypted message within a conversation.
///
/// Messages are always stored encrypted locally (via SQLCipher).
/// The `encryptedContent` field contains the Signal Protocol ciphertext;
/// plaintext is only materialized in memory for display.
struct Message: Identifiable, Codable, Sendable, Equatable {

    /// Unique message identifier (UUID v4, generated client-side).
    let id: String

    /// The conversation this message belongs to.
    let conversationId: String

    /// Fingerprint of the sender's identity key.
    /// Used to attribute messages without revealing identity to the server.
    let senderFingerprint: String

    /// Signal Protocol ciphertext envelope.
    /// Decrypted on-device using the session ratchet state.
    let encryptedContent: Data

    /// Content type for rendering.
    let contentType: ContentType

    /// Server-assigned timestamp (monotonic, not client clock).
    let timestamp: Date

    /// Ephemeral timer in seconds. `nil` means the message persists indefinitely.
    let ephemeralTimer: TimeInterval?

    /// When this message should be auto-deleted (computed from ephemeralTimer + read time).
    var expiresAt: Date?

    /// Delivery and read status.
    var status: Status

    /// Quoted/reply message ID, if this is a reply.
    let replyToId: String?

    /// Attachment metadata (encrypted, stored separately).
    let attachments: [AttachmentRef]

    // MARK: - Nested Types

    enum ContentType: String, Codable, Sendable {
        case text
        case image
        case video
        case audio
        case file
        case voiceNote
        case contact
        case location
        case cryptoPayment
        case systemEvent
    }

    enum Status: String, Codable, Sendable, Equatable {
        /// Message is being encrypted and queued.
        case sending
        /// Message sent to server.
        case sent
        /// Server confirmed delivery to recipient's device.
        case delivered
        /// Recipient has read the message.
        case read
        /// Sending failed (network error, encryption error).
        case failed
    }

    /// Reference to an encrypted attachment stored on CDN.
    struct AttachmentRef: Codable, Sendable, Equatable {
        /// CDN attachment identifier.
        let attachmentId: String
        /// AES-256-GCM key for decrypting the attachment.
        let encryptionKey: Data
        /// SHA-256 digest of the plaintext for integrity verification.
        let digest: Data
        /// MIME type (e.g., "image/jpeg").
        let mimeType: String
        /// File size in bytes (of the encrypted blob).
        let size: Int64
        /// Original filename, if available.
        let filename: String?
        /// Thumbnail data for images/videos (inline, small).
        let thumbnailData: Data?
    }
}

// MARK: - Convenience

extension Message {

    /// Whether this message was sent by the local user.
    func isMine(localFingerprint: String) -> Bool {
        senderFingerprint == localFingerprint
    }

    /// Whether this message has an active ephemeral timer.
    var isEphemeral: Bool {
        ephemeralTimer != nil
    }

    /// Whether this message has expired and should be deleted.
    var hasExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Whether this message has attachments.
    var hasAttachments: Bool {
        !attachments.isEmpty
    }
}
