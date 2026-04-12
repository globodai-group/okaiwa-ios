import Foundation

/// Conversation entity — mirrors `Conversation.kt` on Android.
///
/// Represents a 1:1 or group conversation with metadata about
/// participants, last message preview, and encryption state.
public struct Conversation: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let type: ConversationType
    public var title: String?
    public var avatarUrl: String?
    public var participants: [Participant]
    public var lastMessage: MessagePreview?
    public var unreadCount: Int
    public var isMuted: Bool
    public var isPinned: Bool
    public var isArchived: Bool
    public var muteExpiresAt: Date?
    public var disappearingDurationSeconds: TimeInterval?
    public var folder: ConversationFolder
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        type: ConversationType,
        title: String? = nil,
        avatarUrl: String? = nil,
        participants: [Participant],
        lastMessage: MessagePreview? = nil,
        unreadCount: Int = 0,
        isMuted: Bool = false,
        isPinned: Bool = false,
        isArchived: Bool = false,
        muteExpiresAt: Date? = nil,
        disappearingDurationSeconds: TimeInterval? = nil,
        folder: ConversationFolder = .all,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.avatarUrl = avatarUrl
        self.participants = participants
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.muteExpiresAt = muteExpiresAt
        self.disappearingDurationSeconds = disappearingDurationSeconds
        self.folder = folder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display title: conversation title for groups, participant name for 1:1.
    public var displayTitle: String {
        title ?? participants.first?.displayName ?? "Unknown"
    }

    /// Whether all participants have verified keys.
    public var isFullyVerified: Bool {
        participants.allSatisfy { $0.isKeyVerified }
    }
}

public enum ConversationType: String, Codable, Sendable {
    case oneToOne
    case group
}

public enum ConversationFolder: String, Codable, Sendable {
    case all
    case personal
    case work
    case crypto
    case archived
}

public enum ParticipantRole: String, Codable, Sendable {
    case owner
    case admin
    case member
}

public struct Participant: Hashable, Equatable, Sendable {
    public let userId: String
    public let displayName: String
    public let avatarUrl: String?
    public let role: ParticipantRole
    public let isKeyVerified: Bool
    public let joinedAt: Date

    public init(
        userId: String,
        displayName: String,
        avatarUrl: String? = nil,
        role: ParticipantRole = .member,
        isKeyVerified: Bool = false,
        joinedAt: Date
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
        self.isKeyVerified = isKeyVerified
        self.joinedAt = joinedAt
    }

    public var isAdmin: Bool { role == .admin || role == .owner }
}

/// Lightweight message preview for conversation list display.
public struct MessagePreview: Hashable, Equatable, Sendable {
    public let messageId: String
    public let senderName: String?
    public let content: String
    public let type: MessageType
    public let timestamp: Date

    public init(
        messageId: String,
        senderName: String? = nil,
        content: String,
        type: MessageType = .text,
        timestamp: Date
    ) {
        self.messageId = messageId
        self.senderName = senderName
        self.content = content
        self.type = type
        self.timestamp = timestamp
    }
}
