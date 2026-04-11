// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Repository protocol for chat operations.
///
/// Abstracts the data layer for conversations and messages.
/// Implementations coordinate between:
/// - Local encrypted database (SQLCipher via OkaiwaDB)
/// - WebSocket transport for real-time message delivery
/// - CDN for attachment upload/download
///
/// All methods are async and throw `AppError` on failure.
protocol ChatRepository: Sendable {

    // MARK: - Conversations

    /// Fetch all conversations, optionally filtered by folder.
    ///
    /// Results are sorted by `lastActivityAt` descending.
    ///
    /// - Parameters:
    ///   - folder: Filter by folder. Pass `.all` for no filter.
    ///   - limit: Maximum number of conversations to return.
    ///   - offset: Pagination offset.
    /// - Returns: Array of conversations.
    func getConversations(
        folder: Conversation.Folder,
        limit: Int,
        offset: Int
    ) async throws -> [Conversation]

    /// Get a single conversation by ID.
    func getConversation(id: String) async throws -> Conversation

    /// Create a new one-to-one conversation with a contact.
    ///
    /// If a conversation already exists with this contact, returns the existing one.
    ///
    /// - Parameter contactFingerprint: The contact's identity key fingerprint.
    /// - Returns: The new or existing conversation.
    func createConversation(
        contactFingerprint: String
    ) async throws -> Conversation

    /// Create a new group conversation.
    func createGroupConversation(
        name: String,
        participantFingerprints: [String]
    ) async throws -> Conversation

    /// Delete a conversation and all its messages locally.
    func deleteConversation(id: String) async throws

    /// Pin or unpin a conversation.
    func setConversationPinned(id: String, isPinned: Bool) async throws

    /// Set the ephemeral message timer for a conversation.
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID.
    ///   - seconds: Timer duration in seconds. Pass `nil` to disable.
    func setEphemeralTimer(
        conversationId: String,
        seconds: TimeInterval?
    ) async throws

    // MARK: - Messages

    /// Fetch messages for a conversation, paginated.
    ///
    /// Messages are returned in reverse chronological order (newest first).
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID.
    ///   - before: Fetch messages before this date (for pagination).
    ///   - limit: Maximum number of messages to return.
    /// - Returns: Array of encrypted messages.
    func getMessages(
        conversationId: String,
        before: Date?,
        limit: Int
    ) async throws -> [Message]

    /// Send an encrypted message.
    ///
    /// The message content must already be encrypted via the Signal Protocol
    /// session. This method handles WebSocket delivery and local persistence.
    ///
    /// - Parameter message: The encrypted message to send.
    /// - Returns: The message with updated status (`.sent` or `.failed`).
    @discardableResult
    func sendMessage(_ message: Message) async throws -> Message

    /// Delete a message locally.
    func deleteMessage(id: String, conversationId: String) async throws

    /// Delete a message for everyone in the conversation.
    ///
    /// Sends a deletion request to all participants.
    func deleteMessageForEveryone(id: String, conversationId: String) async throws

    /// Mark all messages in a conversation as read up to a given timestamp.
    func markAsRead(conversationId: String, upTo timestamp: Date) async throws

    // MARK: - Real-time

    /// Stream of incoming messages via WebSocket.
    ///
    /// Returns an `AsyncStream` that emits new messages as they arrive.
    func incomingMessages() -> AsyncStream<Message>

    /// Stream of message status updates (delivered, read).
    func messageStatusUpdates() -> AsyncStream<(messageId: String, status: Message.Status)>

    /// Stream of typing indicators.
    func typingIndicators() -> AsyncStream<(conversationId: String, fingerprint: String, isTyping: Bool)>

    /// Send a typing indicator.
    func sendTypingIndicator(conversationId: String, isTyping: Bool) async throws
}
