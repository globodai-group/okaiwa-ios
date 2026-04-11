// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// View model for the conversation list screen.
///
/// Manages loading, filtering, searching, and real-time updates
/// for the user's conversations.
@Observable
final class ConversationListViewModel {

    // MARK: - State

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: - Properties

    private(set) var conversations: [Conversation] = []
    private(set) var loadState: LoadState = .idle
    var searchText: String = "" {
        didSet { filterConversations() }
    }
    var selectedFolder: Conversation.Folder = .all {
        didSet {
            Task { await loadConversations() }
        }
    }

    private(set) var filteredConversations: [Conversation] = []
    private(set) var totalUnreadCount: Int = 0

    private var chatRepository: ChatRepository?
    private var incomingMessageTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "ConversationListVM")

    private let pageSize = 50

    // MARK: - Initialization

    init() {}

    deinit {
        incomingMessageTask?.cancel()
    }

    // MARK: - Configuration

    func configure(chatRepository: ChatRepository) {
        self.chatRepository = chatRepository
    }

    // MARK: - Loading

    /// Load conversations from the repository.
    func loadConversations() async {
        loadState = .loading
        logger.info("Loading conversations — folder: \(self.selectedFolder.rawValue)")

        do {
            guard let repo = chatRepository else {
                logger.warning("ChatRepository not configured")
                loadState = .loaded
                return
            }

            let loaded = try await repo.getConversations(
                folder: selectedFolder,
                limit: pageSize,
                offset: 0
            )

            conversations = loaded
            filterConversations()
            computeUnreadCount()
            loadState = .loaded
            logger.info("Loaded \(loaded.count) conversations")
        } catch {
            let appError = AppError.from(error)
            loadState = .error(appError.localizedDescription)
            logger.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }

    /// Load more conversations (pagination).
    func loadMore() async {
        guard loadState == .loaded, let repo = chatRepository else { return }

        do {
            let more = try await repo.getConversations(
                folder: selectedFolder,
                limit: pageSize,
                offset: conversations.count
            )

            guard !more.isEmpty else { return }
            conversations.append(contentsOf: more)
            filterConversations()
            logger.info("Loaded \(more.count) more conversations")
        } catch {
            logger.error("Failed to load more: \(error.localizedDescription)")
        }
    }

    /// Start listening for incoming messages to update the conversation list.
    func startListeningForUpdates() {
        guard let repo = chatRepository else { return }

        incomingMessageTask = Task { [weak self] in
            for await message in repo.incomingMessages() {
                guard let self, !Task.isCancelled else { break }

                // Update the conversation's last message and unread count
                if let index = self.conversations.firstIndex(where: { $0.id == message.conversationId }) {
                    var conversation = self.conversations[index]
                    conversation.lastMessage = Conversation.LastMessagePreview(
                        senderUsername: "Contact", // Resolved by lookup in production
                        textPreview: "", // Decrypted in production
                        contentType: message.contentType,
                        timestamp: message.timestamp,
                        status: message.status
                    )
                    conversation.unreadCount += 1
                    conversation.lastActivityAt = message.timestamp

                    self.conversations[index] = conversation
                    self.sortConversations()
                    self.filterConversations()
                    self.computeUnreadCount()
                }

                self.logger.debug("Incoming message updated conversation list")
            }
        }
    }

    /// Stop listening for updates.
    func stopListening() {
        incomingMessageTask?.cancel()
        incomingMessageTask = nil
    }

    // MARK: - Actions

    /// Pin or unpin a conversation.
    func togglePin(for conversation: Conversation) async {
        guard let repo = chatRepository else { return }

        do {
            try await repo.setConversationPinned(id: conversation.id, isPinned: !conversation.isPinned)

            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index].isPinned.toggle()
                sortConversations()
                filterConversations()
            }
        } catch {
            logger.error("Failed to toggle pin: \(error.localizedDescription)")
        }
    }

    /// Delete a conversation.
    func deleteConversation(_ conversation: Conversation) async {
        guard let repo = chatRepository else { return }

        do {
            try await repo.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            filterConversations()
            computeUnreadCount()
            logger.info("Deleted conversation: \(conversation.id.prefix(8))")
        } catch {
            logger.error("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    /// Mark a conversation as read.
    func markAsRead(_ conversation: Conversation) async {
        guard let repo = chatRepository else { return }

        do {
            try await repo.markAsRead(conversationId: conversation.id, upTo: Date())

            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index].unreadCount = 0
                filterConversations()
                computeUnreadCount()
            }
        } catch {
            logger.error("Failed to mark as read: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func filterConversations() {
        if searchText.isEmpty {
            filteredConversations = conversations
        } else {
            let query = searchText.lowercased()
            filteredConversations = conversations.filter { conversation in
                conversation.displayName.lowercased().contains(query) ||
                (conversation.lastMessage?.textPreview.lowercased().contains(query) ?? false)
            }
        }
    }

    private func sortConversations() {
        conversations.sort { a, b in
            // Pinned conversations first, then by last activity
            if a.isPinned != b.isPinned {
                return a.isPinned
            }
            return a.lastActivityAt > b.lastActivityAt
        }
    }

    private func computeUnreadCount() {
        totalUnreadCount = conversations.reduce(0) { $0 + $1.unreadCount }
    }
}
