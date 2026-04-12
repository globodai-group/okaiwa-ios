import Foundation
import Combine

/// Mock conversation graph — mirrors `MockChatRepository.kt` line for
/// line so Android and iOS show the same fixture while the relay + Signal
/// Protocol clients are still under construction.
///
/// The 12 seed conversations stress the same row states we want to
/// review: short / long previews, pinned ordering, unread counts from
/// 0 to 27, voice note / image / crypto-payment preview types, and a
/// mix of 1:1 + group threads in French and English.
public final class MockChatRepository: ObservableObject {
    public static let shared = MockChatRepository()

    @Published private(set) public var conversations: [Conversation]
    private var messagesByConversation: [String: [Message]] = [:]

    public static let meUserId = "me"

    public init() {
        self.conversations = Self.seedConversations()
    }

    public func messages(for conversationId: String) -> [Message] {
        if let existing = messagesByConversation[conversationId] { return existing }
        let seeded = Self.seedMessages(conversationId: conversationId)
        messagesByConversation[conversationId] = seeded
        return seeded
    }

    public func sendMessage(
        conversationId: String,
        content: String,
        replyToMessageId: String? = nil
    ) {
        let message = Message(
            id: "m-\(Date().timeIntervalSince1970)",
            conversationId: conversationId,
            senderId: Self.meUserId,
            plaintextContent: content,
            replyToMessageId: replyToMessageId,
            sentAt: Date()
        )
        var existing = messages(for: conversationId)
        existing.append(message)
        messagesByConversation[conversationId] = existing

        // Bubble the new message into the conversation preview and
        // re-sort by updatedAt so it jumps to the top.
        conversations = conversations.map { conv in
            guard conv.id == conversationId else { return conv }
            var updated = conv
            updated.lastMessage = MessagePreview(
                messageId: message.id,
                senderName: "Moi",
                content: content,
                timestamp: message.sentAt
            )
            updated.updatedAt = message.sentAt
            return updated
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func markAsRead(conversationId: String) {
        conversations = conversations.map { conv in
            guard conv.id == conversationId else { return conv }
            var updated = conv
            updated.unreadCount = 0
            return updated
        }
    }

    // MARK: - Fixtures

    private static func seedConversations() -> [Conversation] {
        let now = Date()
        func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(-offset) }

        return [
            makeConv(id: "c-marie", name: "Marie Dubois", lastText: "À demain à 19h alors 😊",
                     lastAt: at(3 * 60), unread: 2, pinned: true),
            makeConv(id: "c-chris", name: "Chris Sabian", lastText: "Envoyé 250 USDC ✅",
                     lastAt: at(14 * 60), unread: 0, pinned: true, previewType: .cryptoPayment),
            makeConv(id: "c-team", name: "Team Okaiwa", lastText: "Leo: on se voit en visio cet après-midi ?",
                     lastAt: at(42 * 60), unread: 5, type: .group),
            makeConv(id: "c-hao", name: "Hao Tensei",
                     lastText: "Tu as lu le whitepaper ? Je trouve que la section 4 mérite d'être reprise parce que la description de l'architecture zero-knowledge manque de précision.",
                     lastAt: at(2 * 3600), unread: 1),
            makeConv(id: "c-oussama", name: "Oussama", lastText: "🎉🎉",
                     lastAt: at(4 * 3600), unread: 0),
            makeConv(id: "c-payrolless", name: "Payrolless - Cortx",
                     lastText: "Vous venez de recevoir une nouvelle candidature.",
                     lastAt: at(6 * 3600), unread: 27),
            makeConv(id: "c-fidelio", name: "Board FIDELIO", lastText: "Denis: mission accomplie 🔥",
                     lastAt: at(9 * 3600), unread: 0, type: .group),
            makeConv(id: "c-tapbit", name: "TapbitBotX",
                     lastText: "Parfait ! J'ai coupé l'automatisation X comme demandé.",
                     lastAt: at(86_400), unread: 0),
            makeConv(id: "c-leader", name: "LEADER DIABY",
                     lastText: "Soyez disponibles, on va lancer le nouveau module.",
                     lastAt: at(86_400 + 2 * 3600), unread: 0),
            makeConv(id: "c-signal", name: "Okaiwa",
                     lastText: "Bienvenue sur Okaiwa. Vos messages sont chiffrés de bout en bout.",
                     lastAt: at(2 * 86_400), unread: 0, type: .group),
            makeConv(id: "c-luca", name: "Luca Ferrari", lastText: "Voice note",
                     lastAt: at(3 * 86_400), unread: 0, previewType: .voiceNote),
            makeConv(id: "c-sarah", name: "Sarah Benoît", lastText: "Photo",
                     lastAt: at(4 * 86_400), unread: 0, previewType: .image),
        ]
    }

    private static func makeConv(
        id: String,
        name: String,
        lastText: String,
        lastAt: Date,
        unread: Int,
        pinned: Bool = false,
        type: ConversationType = .oneToOne,
        previewType: MessageType = .text
    ) -> Conversation {
        Conversation(
            id: id,
            type: type,
            title: type == .group ? name : nil,
            participants: [
                Participant(userId: "u-\(id)", displayName: name, joinedAt: lastAt)
            ],
            lastMessage: MessagePreview(
                messageId: "mp-\(id)",
                senderName: nil,
                content: lastText,
                type: previewType,
                timestamp: lastAt
            ),
            unreadCount: unread,
            isPinned: pinned,
            createdAt: lastAt.addingTimeInterval(-7 * 86_400),
            updatedAt: lastAt
        )
    }

    private static func seedMessages(conversationId: String) -> [Message] {
        let now = Date()
        let them = String(conversationId.dropFirst(2))
        func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(-offset) }
        return [
            mk(conversationId, them, "Hey ! Tu as testé la beta ?", at(2 * 3600), mine: false),
            mk(conversationId, them, "Oui, franchement le design est propre. La bar flottante est classe.", at(2 * 3600 - 60), mine: true),
            mk(conversationId, them, "Carrément ! Et le wallet intégré dans les chats, c'est le move.", at(2 * 3600 - 120), mine: false),
            mk(conversationId, them, "On pourra envoyer de l'USDC entre potes sans avoir à copier-coller d'adresse.", at(2 * 3600 - 180), mine: false),
            mk(conversationId, them, "Exactement l'idée. Signal + Telegram + TrustWallet en un.", at(3600 + 40 * 60), mine: true),
            mk(conversationId, them, "J'attends la release stable 🚀", at(3600), mine: false),
            mk(conversationId, them, "Début de la semaine pro normalement.", at(30 * 60), mine: true),
            mk(conversationId, them, "Tu me tiens au courant ?", at(10 * 60), mine: false),
            mk(conversationId, them, "Évidemment 💪", at(5 * 60), mine: true),
        ]
    }

    private static func mk(_ conversationId: String, _ otherId: String, _ content: String, _ at: Date, mine: Bool) -> Message {
        Message(
            id: "m-\(conversationId)-\(at.timeIntervalSince1970)",
            conversationId: conversationId,
            senderId: mine ? meUserId : otherId,
            plaintextContent: content,
            sentAt: at
        )
    }
}
