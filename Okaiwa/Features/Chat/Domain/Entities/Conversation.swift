// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// A conversation (thread) between two or more participants.
///
/// Conversations can be one-to-one or group chats. They hold metadata
/// about participants, ephemeral settings, and organizational state.
struct Conversation: Identifiable, Codable, Sendable, Equatable {

    /// Unique conversation identifier (UUID v4).
    let id: String

    /// Participants' identity key fingerprints.
    let participants: [Participant]

    /// The most recent message in this conversation (for list preview).
    var lastMessage: LastMessagePreview?

    /// Number of unread messages.
    var unreadCount: Int

    /// Ephemeral message timer in seconds. `nil` means messages persist.
    var ephemeralTimerSeconds: TimeInterval?

    /// Whether this conversation is pinned to the top.
    var isPinned: Bool

    /// Whether this conversation is archived.
    var isArchived: Bool

    /// Whether this conversation is muted.
    var isMuted: Bool

    /// Mute expiration date. `nil` means muted indefinitely.
    var muteExpiresAt: Date?

    /// Organizational folder.
    var folder: Folder

    /// Conversation type.
    let type: ConversationType

    /// Group metadata (only for group conversations).
    var groupInfo: GroupInfo?

    /// When this conversation was created.
    let createdAt: Date

    /// Last activity timestamp (for sorting).
    var lastActivityAt: Date

    // MARK: - Nested Types

    struct Participant: Codable, Sendable, Equatable {
        let fingerprint: String
        let username: String
        let role: Role

        enum Role: String, Codable, Sendable {
            case member
            case admin
            case owner
        }
    }

    struct LastMessagePreview: Codable, Sendable, Equatable {
        let senderUsername: String
        /// Decrypted text preview (first 100 chars). Empty for non-text.
        let textPreview: String
        let contentType: Message.ContentType
        let timestamp: Date
        let status: Message.Status
    }

    enum ConversationType: String, Codable, Sendable {
        case oneToOne
        case group
    }

    enum Folder: String, Codable, Sendable, CaseIterable {
        case all
        case personal
        case work
        case crypto
        case archived
    }

    struct GroupInfo: Codable, Sendable, Equatable {
        let name: String
        let description: String?
        let avatarAttachmentId: String?
        let maxMembers: Int
        /// Whether only admins can send messages.
        let isAnnounceOnly: Bool
    }
}

// MARK: - Convenience

extension Conversation {

    /// Display name for the conversation.
    var displayName: String {
        switch type {
        case .oneToOne:
            // Show the other participant's username
            return participants.first(where: { $0.role != .owner })?.username
                ?? participants.first?.username
                ?? "Unknown"
        case .group:
            return groupInfo?.name ?? "Group Chat"
        }
    }

    /// Whether the conversation has an active ephemeral timer.
    var hasEphemeralTimer: Bool {
        ephemeralTimerSeconds != nil
    }

    /// Whether the conversation is effectively muted right now.
    var isEffectivelyMuted: Bool {
        guard isMuted else { return false }
        if let expiresAt = muteExpiresAt {
            return Date() < expiresAt
        }
        return true // Muted indefinitely
    }

    /// Formatted ephemeral timer for display.
    var ephemeralTimerDisplay: String? {
        guard let seconds = ephemeralTimerSeconds else { return nil }
        switch seconds {
        case ..<60: return "\(Int(seconds))s"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}
