import Foundation

/// Chat message entity — mirrors `Message.kt` on Android.
///
/// Messages are always encrypted locally and in transit;
/// `plaintextContent` only exists after decryption in memory.
public struct Message: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public var plaintextContent: String?
    public var encryptedPayload: Data?
    public var type: MessageType
    public var status: MessageStatus
    public var replyToMessageId: String?
    public var attachments: [Attachment]
    public var disappearingDurationSeconds: TimeInterval?
    public let sentAt: Date
    public var deliveredAt: Date?
    public var readAt: Date?
    public var editedAt: Date?

    public init(
        id: String,
        conversationId: String,
        senderId: String,
        plaintextContent: String? = nil,
        encryptedPayload: Data? = nil,
        type: MessageType = .text,
        status: MessageStatus = .sending,
        replyToMessageId: String? = nil,
        attachments: [Attachment] = [],
        disappearingDurationSeconds: TimeInterval? = nil,
        sentAt: Date,
        deliveredAt: Date? = nil,
        readAt: Date? = nil,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.plaintextContent = plaintextContent
        self.encryptedPayload = encryptedPayload
        self.type = type
        self.status = status
        self.replyToMessageId = replyToMessageId
        self.attachments = attachments
        self.disappearingDurationSeconds = disappearingDurationSeconds
        self.sentAt = sentAt
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.editedAt = editedAt
    }
}

public enum MessageType: String, Codable, Sendable {
    case text
    case image
    case video
    case audio
    case voiceNote
    case file
    case location
    case contact
    case cryptoPayment
    case system
}

public enum MessageStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

public struct Attachment: Hashable, Equatable, Sendable, Identifiable {
    public let id: String
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let encryptedUrl: String?
    public let thumbnailUrl: String?
    public let width: Int?
    public let height: Int?
    public let durationMs: Int64?
    public let encryptionKey: Data?
    public let digest: Data?

    public init(
        id: String,
        fileName: String,
        mimeType: String,
        sizeBytes: Int64,
        encryptedUrl: String? = nil,
        thumbnailUrl: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int64? = nil,
        encryptionKey: Data? = nil,
        digest: Data? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.encryptedUrl = encryptedUrl
        self.thumbnailUrl = thumbnailUrl
        self.width = width
        self.height = height
        self.durationMs = durationMs
        self.encryptionKey = encryptionKey
        self.digest = digest
    }
}
