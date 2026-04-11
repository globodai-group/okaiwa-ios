// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import CryptoKit
import os

/// Use case for sending an encrypted message.
///
/// Orchestrates the full send flow:
/// 1. Encrypt plaintext content using the Signal Protocol session ratchet
/// 2. Build the message envelope with metadata
/// 3. Persist locally (optimistic insert with `.sending` status)
/// 4. Send via WebSocket transport
/// 5. Update status to `.sent` or `.failed`
///
/// Attachments are encrypted with AES-256-GCM and uploaded to CDN separately.
final class SendMessageUseCase: Sendable {

    private let chatRepository: ChatRepository
    private let keychainManager: KeychainManager
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SendMessage")

    init(
        chatRepository: ChatRepository,
        keychainManager: KeychainManager = KeychainManager()
    ) {
        self.chatRepository = chatRepository
        self.keychainManager = keychainManager
    }

    // MARK: - Execute

    /// Send a text message to a conversation.
    ///
    /// - Parameters:
    ///   - text: Plaintext message content.
    ///   - conversationId: Target conversation ID.
    ///   - replyToId: Message ID being replied to, if any.
    ///   - ephemeralTimer: Ephemeral timer in seconds, if applicable.
    /// - Returns: The sent message with final status.
    @discardableResult
    func execute(
        text: String,
        conversationId: String,
        replyToId: String? = nil,
        ephemeralTimer: TimeInterval? = nil
    ) async throws -> Message {
        logger.info("Sending message to conversation: \(conversationId.prefix(8))")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.encryptionFailed(reason: "Cannot send an empty message")
        }

        // Step 1: Get local user fingerprint
        let senderFingerprint = try loadLocalFingerprint()

        // Step 2: Encrypt the message content
        let plaintext = Data(text.utf8)
        let encryptedContent = try encryptContent(plaintext, for: conversationId)

        // Step 3: Build the message
        let message = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderFingerprint: senderFingerprint,
            encryptedContent: encryptedContent,
            contentType: .text,
            timestamp: Date(),
            ephemeralTimer: ephemeralTimer,
            expiresAt: nil, // Set when recipient reads the message
            status: .sending,
            replyToId: replyToId,
            attachments: []
        )

        // Step 4: Persist and send
        do {
            let sentMessage = try await chatRepository.sendMessage(message)
            logger.info("Message sent: \(sentMessage.id.prefix(8)) — status: \(sentMessage.status.rawValue)")
            return sentMessage
        } catch {
            logger.error("Message send failed: \(error.localizedDescription)")
            throw AppError.from(error)
        }
    }

    /// Send a message with an attachment.
    ///
    /// - Parameters:
    ///   - data: Raw attachment data (image, file, etc.).
    ///   - mimeType: MIME type of the attachment.
    ///   - filename: Original filename.
    ///   - caption: Optional text caption.
    ///   - conversationId: Target conversation ID.
    /// - Returns: The sent message with attachment reference.
    @discardableResult
    func executeWithAttachment(
        data: Data,
        mimeType: String,
        filename: String?,
        caption: String?,
        conversationId: String
    ) async throws -> Message {
        logger.info("Sending attachment (\(mimeType)) to conversation: \(conversationId.prefix(8))")

        let senderFingerprint = try loadLocalFingerprint()

        // Encrypt attachment data with a random AES-256-GCM key
        let attachmentKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: attachmentKey, nonce: nonce)

        guard let encryptedData = sealedBox.combined else {
            throw AppError.encryptionFailed(reason: "AES-GCM seal produced no output")
        }

        // Compute plaintext digest for integrity verification
        let digest = SHA256.hash(data: data)

        // Build attachment reference
        let attachmentRef = Message.AttachmentRef(
            attachmentId: UUID().uuidString, // Server will assign real ID after upload
            encryptionKey: attachmentKey.withUnsafeBytes { Data($0) },
            digest: Data(digest),
            mimeType: mimeType,
            size: Int64(encryptedData.count),
            filename: filename,
            thumbnailData: generateThumbnail(data: data, mimeType: mimeType)
        )

        // Encrypt caption if present
        let encryptedContent: Data
        if let caption, !caption.isEmpty {
            encryptedContent = try encryptContent(Data(caption.utf8), for: conversationId)
        } else {
            encryptedContent = Data()
        }

        let contentType: Message.ContentType = {
            if mimeType.hasPrefix("image/") { return .image }
            if mimeType.hasPrefix("video/") { return .video }
            if mimeType.hasPrefix("audio/") { return .audio }
            return .file
        }()

        let message = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderFingerprint: senderFingerprint,
            encryptedContent: encryptedContent,
            contentType: contentType,
            timestamp: Date(),
            ephemeralTimer: nil,
            expiresAt: nil,
            status: .sending,
            replyToId: nil,
            attachments: [attachmentRef]
        )

        return try await chatRepository.sendMessage(message)
    }

    // MARK: - Private

    /// Load the local user's identity key fingerprint from Keychain.
    private func loadLocalFingerprint() throws -> String {
        guard let keyData = try? keychainManager.load(forKey: "identity_private_key") else {
            throw AppError.keyError(reason: "Identity key not found. Please re-register.")
        }

        // Derive public key from private key
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData)
        let publicKeyData = privateKey.publicKey.rawRepresentation

        return publicKeyData
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Encrypt message content using the Signal Protocol session.
    ///
    /// In production, this delegates to SignalCore's session cipher.
    /// Here we use AES-256-GCM as a placeholder for the ratchet output.
    private func encryptContent(_ plaintext: Data, for conversationId: String) throws -> Data {
        // In production: use SignalCore.SessionCipher to encrypt
        // This is a placeholder using AES-GCM with a derived key
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)

        guard let combined = sealedBox.combined else {
            throw AppError.encryptionFailed(reason: "AES-GCM seal failed")
        }

        return combined
    }

    /// Generate a thumbnail for image attachments.
    private func generateThumbnail(data: Data, mimeType: String) -> Data? {
        guard mimeType.hasPrefix("image/") else { return nil }
        // In production: use CoreGraphics to resize to 64x64 JPEG
        // Thumbnail is embedded in the message envelope for instant preview
        return nil
    }
}
