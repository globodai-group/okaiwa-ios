// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import LibSignalClient
import Combine
import os

/// Production chat repository — iOS twin of
/// `RemoteChatRepository.kt`. Stitches:
///   - GRDB + SQLCipher (`OkaiwaDatabase.conversationDao` / `messageDao`)
///   - libsignal `SessionBuilder` / `signalEncrypt`
///   - the relay's store-and-forward inbox (`RelayAPIClient`)
///
/// Outbound path (`sendMessage`):
///   1. Look up the conversation row → peerDeviceId + peerIdentityKey.
///   2. If no Signal session exists for the peer, fetch the PreKey
///      bundle from the identity service and drive
///      `processPreKeyBundle(…)` — with TOFU + kyber-null + opk-null
///      enforcement along the way.
///   3. `signalEncrypt(…)` → `CiphertextMessage`.
///   4. Base64 the serialised bytes + POST `/v1/messages/send` with
///      the deviceToken bearer AND the senderDeviceId + senderAccountId
///      cross-check the backend validator expects.
///   5. Persist a MessageEntity locally with `.sent`.
///
/// Inbound path lives in `MessagePollingService.swift`.
///
/// Logging policy: NEVER log message body, plaintext, decrypted bytes,
/// identity keys, accountId, deviceId, tokens, or the peerIdentityKey.
/// `os_log` uses `privacy: .private` for accountId mirroring the
/// convention already established in `SessionStore`.
///
/// Published as an `ObservableObject` so SwiftUI views swap
/// `MockChatRepository.shared` for `RemoteChatRepository.shared` with a
/// one-line `@ObservedObject` change.
public final class RemoteChatRepository: ObservableObject {
    public static let shared = RemoteChatRepository()

    private let conversationDao: ConversationDao
    private let messageDao: MessageDao
    private let relayClient: RelayAPIClient
    private let keyClient: KeyAPIClient
    private let discoveryClient: DiscoveryAPIClient
    private let sessionProvider: @Sendable () async -> SessionStore.Session?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "RemoteChatRepo")

    /// Signal protocol device index. Single-device per account today;
    /// multi-device lands with a server-side device registry.
    public static let defaultDeviceIndex: UInt32 = 1
    public static let meSenderId: String = "me"
    private static let previewMaxLen: Int = 120

    /// SwiftUI-observable rehydration of the conversation list —
    /// populated from the `ConversationDao.observeAll()` stream.
    @Published public private(set) var conversations: [Conversation] = []

    private var observationTask: Task<Void, Never>?

    public init(
        database: OkaiwaDatabase = .shared,
        relayClient: RelayAPIClient = RelayAPIClient(),
        keyClient: KeyAPIClient = KeyAPIClient(),
        discoveryClient: DiscoveryAPIClient = DiscoveryAPIClient(),
        sessionProvider: (@Sendable () async -> SessionStore.Session?)? = nil
    ) {
        self.conversationDao = database.conversationDao
        self.messageDao = database.messageDao
        self.relayClient = relayClient
        self.keyClient = keyClient
        self.discoveryClient = discoveryClient
        if let sessionProvider {
            self.sessionProvider = sessionProvider
        } else {
            // Default hops to MainActor because SessionStore.shared +
            // `current` are both @MainActor-isolated. The extra
            // actor hop is negligible relative to the network call
            // that follows and keeps the Swift concurrency checker
            // happy under strict mode.
            self.sessionProvider = {
                await MainActor.run { SessionStore.shared.current }
            }
        }
        observationTask = Task { [weak self] in
            await self?.startObservingConversations()
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Observation

    private func startObservingConversations() async {
        for await rows in conversationDao.observeAll() {
            let mapped = rows.map(Self.toDomain)
            await MainActor.run { [weak self] in
                self?.conversations = mapped
            }
        }
    }

    /// AsyncStream of messages for a given conversation. Views call
    /// this from a `.task { }` and cancel naturally on disappearance.
    public func observeMessages(conversationId: String) -> AsyncStream<[Message]> {
        let dao = messageDao
        return AsyncStream { continuation in
            let task = Task {
                for await rows in dao.observeForConversation(conversationId) {
                    continuation.yield(rows.map(Self.toDomain))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Send

    /// Send a plaintext message over the Signal session. Throws if the
    /// session can't be built (TOFU mismatch, kyber-null bundle,
    /// missing deviceToken). Returns the persisted domain-level
    /// `Message` with its final delivery state.
    @discardableResult
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToMessageId: String? = nil
    ) async throws -> Message {
        guard let session = await sessionProvider() else {
            throw AppError.sessionExpired
        }
        let deviceToken = session.deviceToken
        guard !deviceToken.isEmpty else {
            throw AppError.sessionExpired
        }
        // senderDeviceId / senderAccountId on the relay envelope are
        // cross-checked against the deviceToken's embedded deviceId on
        // the backend (okaiwa-server@dc897f1). Empty values would make
        // every send return 401 "device mismatch" — surface a clean
        // local error so the UI can trigger a re-auth.
        guard !session.deviceId.isEmpty, !session.accountId.isEmpty else {
            throw AppError.sessionExpired
        }

        guard let conversation = try await conversationDao.findById(conversationId) else {
            throw AppError.invalidResponse(detail: "Conversation \(conversationId) not found")
        }

        let peerAddress = try ProtocolAddress(
            name: conversation.peerAccountId,
            deviceId: Self.defaultDeviceIndex
        )

        let store = try SignalIdentityKeys.protocolStore()

        // Lazy session establishment — build from the PreKey bundle
        // if we've never talked to this address before. libsignal's
        // InMemorySignalProtocolStore doesn't expose a
        // `containsSession` helper, so we poll the store directly.
        let existingSession = try? store.loadSession(
            for: peerAddress,
            context: NullContext()
        )
        if existingSession == nil {
            try await buildSession(address: peerAddress, conversation: conversation)
        }

        let plaintext = Data(content.utf8)
        let ciphertext: CiphertextMessage
        do {
            let localAddress = try ProtocolAddress(
                name: "self.\(session.accountId)",
                deviceId: Self.defaultDeviceIndex
            )
            ciphertext = try signalEncrypt(
                message: plaintext,
                for: peerAddress,
                localAddress: localAddress,
                sessionStore: store,
                identityStore: store,
                context: NullContext()
            )
        } catch {
            logger.error("encrypt failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.encryptionFailed(reason: error.localizedDescription)
        }
        let blobBase64 = try ciphertext.serialize().base64EncodedString()
        let messageId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        // Sender envelope (mirror of Android P0 fix in dc897f1): the
        // backend validator cross-checks senderDeviceId against the
        // deviceToken's embedded deviceId. `senderAccountId` lets the
        // receiver route the decrypted payload without a second lookup.
        let request = SendMessageRequest(
            recipientDeviceId: conversation.peerDeviceId,
            blob: blobBase64,
            messageId: messageId,
            senderDeviceId: session.deviceId,
            senderAccountId: session.accountId
        )

        var deliveryState = DeliveryState.sent
        do {
            _ = try await relayClient.sendMessage(deviceToken: deviceToken, body: request)
        } catch {
            logger.warning("relay send threw — persisting as FAILED")
            deliveryState = DeliveryState.failed
        }

        return try await persistOutbound(
            messageId: messageId,
            conversationId: conversationId,
            body: content,
            state: deliveryState,
            now: now,
            session: session
        )
    }

    private func persistOutbound(
        messageId: String,
        conversationId: String,
        body: String,
        state: String,
        now: Int64,
        session: SessionStore.Session
    ) async throws -> Message {
        let row = MessageEntity(
            id: messageId,
            conversationId: conversationId,
            senderDeviceId: session.deviceId,
            body: body,
            timestamp: now,
            isOutbound: true,
            deliveryState: state
        )
        try await messageDao.insert(row)
        try await conversationDao.updateLastMessage(
            conversationId: conversationId,
            messageId: messageId,
            preview: String(body.prefix(Self.previewMaxLen)),
            at: now
        )

        let status: MessageStatus = {
            switch state {
            case DeliveryState.sent:      return .sent
            case DeliveryState.delivered: return .delivered
            case DeliveryState.failed:    return .failed
            default:                      return .sending
            }
        }()

        return Message(
            id: messageId,
            conversationId: conversationId,
            senderId: Self.meSenderId,
            plaintextContent: body,
            type: .text,
            status: status,
            sentAt: Date(timeIntervalSince1970: Double(now) / 1000.0)
        )
    }

    // MARK: - Session build (X3DH/PQXDH)

    private func buildSession(
        address: ProtocolAddress,
        conversation: ConversationEntity
    ) async throws {
        let bundleResponse: FetchPreKeyResponse
        do {
            bundleResponse = try await keyClient.fetchPreKey(deviceId: conversation.peerDeviceId)
        } catch KeyAPIError.notFound {
            throw AppError.preKeyExhausted
        }

        // ─────────────────────────────────────────────────────────
        // TOFU on the peer's identityKey (mirror of Android P0 #1).
        // The relay is untrusted — a compromised server can swap
        // `body.identityKey` to its own and silently MITM every
        // session built afterwards. Pin on first contact and refuse
        // the build if the key has changed since.
        // ─────────────────────────────────────────────────────────
        if !conversation.peerIdentityKey.isEmpty,
           conversation.peerIdentityKey != bundleResponse.identityKey {
            logger.error("peer identity key changed — refusing to encrypt (conv \(conversation.id, privacy: .private))")
            throw AppError.safetyNumberMismatch
        }
        if conversation.peerIdentityKey.isEmpty {
            // First contact via this code path (outbound) — pin now.
            try await conversationDao.updatePeerIdentity(
                conversationId: conversation.id,
                peerIdentityKey: bundleResponse.identityKey,
                peerRegistrationId: bundleResponse.registrationId
            )
        }

        // ─────────────────────────────────────────────────────────
        // Kyber required (mirror of Android P0 #9). libsignal 0.92's
        // PreKeyBundle requires a kyberPreKey; a `kyberPreKey: null`
        // bundle means the peer is pre-commit. DEFER the send with a
        // clean error rather than building a broken session.
        // ─────────────────────────────────────────────────────────
        guard let kyber = bundleResponse.kyberPreKey else {
            logger.error("peer bundle missing kyberPreKey — deferring send")
            throw AppError.preKeyExhausted
        }

        guard let identityBytes = Data(base64Encoded: bundleResponse.identityKey),
              let signedPublicBytes = Data(base64Encoded: bundleResponse.signedPreKey.publicKey),
              let signedSignatureBytes = Data(base64Encoded: bundleResponse.signedPreKey.signature),
              let kyberPublicBytes = Data(base64Encoded: kyber.publicKey),
              let kyberSignatureBytes = Data(base64Encoded: kyber.signature) else {
            throw AppError.invalidResponse(detail: "Malformed base64 in peer bundle")
        }

        let identityKey = try IdentityKey(bytes: identityBytes)
        let signedPublic = try PublicKey(signedPublicBytes)
        let kyberPublic = try KEMPublicKey(kyberPublicBytes)

        let bundle: PreKeyBundle
        if let oneTime = bundleResponse.preKey {
            // Bundle with an OPK — dedicated libsignal initializer.
            guard let opkBytes = Data(base64Encoded: oneTime.publicKey) else {
                throw AppError.invalidResponse(detail: "Malformed OPK base64")
            }
            let opkPublic = try PublicKey(opkBytes)
            bundle = try PreKeyBundle(
                registrationId: UInt32(bundleResponse.registrationId),
                deviceId: Self.defaultDeviceIndex,
                prekeyId: UInt32(oneTime.keyId),
                prekey: opkPublic,
                signedPrekeyId: UInt32(bundleResponse.signedPreKey.keyId),
                signedPrekey: signedPublic,
                signedPrekeySignature: signedSignatureBytes,
                identity: identityKey,
                kyberPrekeyId: UInt32(kyber.keyId),
                kyberPrekey: kyberPublic,
                kyberPrekeySignature: kyberSignatureBytes
            )
        } else {
            // OPK-null fallback (mirror of Android P0 #10). libsignal's
            // Swift API has a dedicated initializer that simply omits
            // the `prekey` / `prekeyId` parameters — no sentinel int
            // needed like on the Kotlin port. The receiver knows the
            // OPK was skipped because the PreKeySignalMessage
            // envelope's bitmap signals it (verified against
            // libsignal v0.92.1 swift/Sources/LibSignalClient/state/
            // PreKeyBundle.swift).
            bundle = try PreKeyBundle(
                registrationId: UInt32(bundleResponse.registrationId),
                deviceId: Self.defaultDeviceIndex,
                signedPrekeyId: UInt32(bundleResponse.signedPreKey.keyId),
                signedPrekey: signedPublic,
                signedPrekeySignature: signedSignatureBytes,
                identity: identityKey,
                kyberPrekeyId: UInt32(kyber.keyId),
                kyberPrekey: kyberPublic,
                kyberPrekeySignature: kyberSignatureBytes
            )
        }

        let store = try SignalIdentityKeys.protocolStore()
        try processPreKeyBundle(
            bundle,
            for: address,
            sessionStore: store,
            identityStore: store,
            context: NullContext()
        )
    }

    // MARK: - Conversation create / lookup

    /// Create (or return) a conversation from a discovery hit. Called
    /// by the NewMessage screen once the user taps "Démarrer" on a
    /// discovery result. Persists the peer's deviceId + identity key
    /// so `sendMessage` doesn't need another discovery round-trip.
    @discardableResult
    public func createConversationFromDiscovery(
        peer: DiscoveredUser
    ) async throws -> Conversation {
        if let existing = try await conversationDao.findByPeerAccountId(peer.accountId) {
            return Self.toDomain(existing)
        }
        guard let peerDeviceId = peer.deviceId else {
            throw AppError.invalidResponse(
                detail: "Discovered user \(peer.accountId) has no deviceId"
            )
        }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let conversationId = UUID().uuidString
        let entity = ConversationEntity(
            id: conversationId,
            peerAccountId: peer.accountId,
            peerUsername: peer.username,
            peerDisplayName: peer.profile?.displayName ?? peer.username,
            peerDeviceId: peerDeviceId,
            peerRegistrationId: peer.registrationId,
            peerIdentityKey: peer.identityPublicKey,
            lastMessageAt: 0,
            unreadCount: 0,
            createdAt: now,
            updatedAt: now
        )
        try await conversationDao.insert(entity)
        return Self.toDomain(entity)
    }

    public func markAsRead(conversationId: String) async throws {
        try await conversationDao.clearUnread(conversationId: conversationId)
    }

    public func deleteMessage(id: String) async throws {
        try await messageDao.deleteById(id)
    }

    // MARK: - Domain mapping

    private static func toDomain(_ entity: ConversationEntity) -> Conversation {
        let created = Date(timeIntervalSince1970: Double(entity.createdAt) / 1000.0)
        let updated = Date(timeIntervalSince1970: Double(entity.updatedAt) / 1000.0)
        let participant = Participant(
            userId: entity.peerAccountId,
            displayName: entity.peerDisplayName ?? entity.peerUsername ?? entity.peerAccountId,
            avatarUrl: nil,
            role: .member,
            isKeyVerified: false,
            joinedAt: created
        )
        let preview: MessagePreview? = entity.lastMessageId.map { id in
            MessagePreview(
                messageId: id,
                senderName: nil,
                content: entity.lastMessagePreview ?? "",
                type: .text,
                timestamp: Date(timeIntervalSince1970: Double(entity.lastMessageAt) / 1000.0)
            )
        }
        return Conversation(
            id: entity.id,
            type: .oneToOne,
            title: nil,
            avatarUrl: nil,
            participants: [participant],
            lastMessage: preview,
            unreadCount: entity.unreadCount,
            createdAt: created,
            updatedAt: updated
        )
    }

    private static func toDomain(_ entity: MessageEntity) -> Message {
        let status: MessageStatus = {
            switch entity.deliveryState {
            case DeliveryState.pending:   return .sending
            case DeliveryState.sent:      return .sent
            case DeliveryState.delivered: return .delivered
            case DeliveryState.failed:    return .failed
            default:                      return .sent
            }
        }()
        return Message(
            id: entity.id,
            conversationId: entity.conversationId,
            senderId: entity.isOutbound ? meSenderId : entity.senderDeviceId,
            plaintextContent: entity.body,
            type: .text,
            status: status,
            sentAt: Date(timeIntervalSince1970: Double(entity.timestamp) / 1000.0)
        )
    }
}
