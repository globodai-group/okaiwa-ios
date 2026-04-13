// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import LibSignalClient
import os

/// Polls the relay inbox and decrypts/persists every envelope — iOS
/// twin of `MessagePollingService.kt`.
///
/// Lifecycle: `start()` / `stop()` pair is driven from the root view's
/// `.task { }` so we don't drain battery on the lock screen. Every
/// `Self.pollIntervalSeconds` we:
///   1. GET `/v1/messages/pending` (body on GET — backend quirk).
///   2. For each envelope:
///      a. Sniff the CiphertextMessage type byte.
///      b. If PreKey → build a `PreKeySignalMessage`, capture its
///         embedded identityKey BEFORE decrypt (TOFU pin), then run
///         `signalDecryptPreKey`.
///      c. If Whisper → build a `SignalMessage`, run `signalDecrypt`.
///      d. Resolve / create the ConversationEntity, pinning the
///         extracted identityKey on the freshly-created row (so the
///         next reply's TOFU check has something real to compare
///         against — review P0 #2).
///      e. Insert MessageEntity (isOutbound=false, delivered).
///      f. DELETE `/v1/messages/:id` to ack. `INSERT OR IGNORE` makes
///         a post-crash replay idempotent.
///
/// Dead-letter (review P0 #4): per-messageId decrypt failure counts
/// are tracked in-process. After `maxDecryptRetries` consecutive
/// failures we ack + drop so a poison envelope can't drain the inbox.
/// `DuplicateMessageException` equivalents (libsignal surfaces a
/// typed error) → ack immediately.
///
/// Logging policy matches `RemoteChatRepository`: NEVER log plaintext
/// / bodies / identity keys / accountId / deviceId / tokens.
public final class MessagePollingService: @unchecked Sendable {
    public static let shared = MessagePollingService()

    private let conversationDao: ConversationDao
    private let messageDao: MessageDao
    private let deadLetterDao: DeadLetterDao
    private let relayClient: RelayAPIClient
    private let discoveryClient: DiscoveryAPIClient
    private let sessionProvider: @Sendable () async -> SessionStore.Session?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "MsgPolling")

    /// 5 s matches Android. Good trade-off between freshness and
    /// battery. When we wire a push channel this falls to 60 s with
    /// socket wakeups.
    private static let pollIntervalSeconds: UInt64 = 5
    /// Length cap for `lastMessagePreview` so a long message doesn't
    /// bloat the conversation list row. Matches Android exactly.
    private static let previewMaxLen: Int = 120
    /// After this many consecutive decrypt failures on the same
    /// envelope, dead-letter it (ack + drop). 5 ≈ 25 s of polling.
    private static let maxDecryptRetries: Int = 5

    /// In-memory dead-letter counter — `messageId → consecutive
    /// decrypt failure count`. Per-process reset is fine: at-least-
    /// once still applies and a poison blob will hit the limit again
    /// quickly on the next launch.
    private var decryptFailureCounts: [String: Int] = [:]
    private let counterQueue = DispatchQueue(label: "io.okaiwa.polling.counters")

    /// Serialises the spoof-defense `findByIdentityKeyExcluding`
    /// check + `insert` pair in [resolveOrCreateConversation]. Without
    /// it, two concurrent inbound envelopes from different accountIds
    /// that claim the same identityKey could both pass the collision
    /// check before either inserts — letting a hostile relay silently
    /// mint duplicate sessions for one peer's identity (TOCTOU, P1
    /// from the cross-platform security review, mirror of Android's
    /// `resolveMutex`).
    ///
    /// Backed by an empty actor so every async call re-enters through
    /// actor isolation — Swift's runtime guarantees serial execution.
    private let resolveLock = ResolveLock()

    private actor ResolveLock {
        func withLock<T: Sendable>(_ op: () async throws -> T) async rethrows -> T {
            try await op()
        }
    }

    private var pollingTask: Task<Void, Never>?

    public init(
        database: OkaiwaDatabase = .shared,
        relayClient: RelayAPIClient = RelayAPIClient(),
        discoveryClient: DiscoveryAPIClient = DiscoveryAPIClient(),
        sessionProvider: (@Sendable () async -> SessionStore.Session?)? = nil
    ) {
        self.conversationDao = database.conversationDao
        self.messageDao = database.messageDao
        self.deadLetterDao = database.deadLetterDao
        self.relayClient = relayClient
        self.discoveryClient = discoveryClient
        if let sessionProvider {
            self.sessionProvider = sessionProvider
        } else {
            // SessionStore is @MainActor — hop there from the
            // background polling Task. Negligible overhead vs. the
            // network call that follows.
            self.sessionProvider = {
                await MainActor.run { SessionStore.shared.current }
            }
        }
    }

    /// Idempotent — a subsequent `start()` while the loop is running is
    /// a no-op.
    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.pollOnce()
                } catch {
                    self.logger.warning("poll failed — \(type(of: error), privacy: .public)")
                }
                try? await Task.sleep(nanoseconds: Self.pollIntervalSeconds * 1_000_000_000)
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Loop body

    private func pollOnce() async throws {
        guard let session = await sessionProvider() else { return }
        let deviceToken = session.deviceToken
        let deviceId = session.deviceId
        guard !deviceToken.isEmpty, !deviceId.isEmpty else { return }

        let response: PendingMessagesResponse
        do {
            response = try await relayClient.getPending(
                deviceToken: deviceToken,
                body: PendingMessagesRequest(deviceId: deviceId)
            )
        } catch {
            logger.warning("pending — \(type(of: error), privacy: .public)")
            return
        }
        guard response.count > 0 else { return }
        logger.debug("polled \(response.count, privacy: .public) envelopes")

        for envelope in response.messages {
            do {
                try await handleEnvelope(envelope, deviceToken: deviceToken)
            } catch SignalError.duplicatedMessage {
                // Already-seen message — ack immediately. The ratchet
                // moved past this index; re-decrypt would always fail.
                // Mirror of Android's DuplicateMessageException handling.
                logger.debug("duplicate envelope — ack + drop")
                await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
                await resetFailureCounter(for: envelope.messageId)
            } catch {
                let next = await bumpFailureCounter(for: envelope.messageId)
                if next >= Self.maxDecryptRetries {
                    logger.warning(
                        "envelope dead-lettered after \(next, privacy: .public) attempts — ack + drop"
                    )
                    await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
                    await resetFailureCounter(for: envelope.messageId)
                } else {
                    logger.warning(
                        "envelope handle failed (attempt \(next, privacy: .public)/\(Self.maxDecryptRetries, privacy: .public))"
                    )
                }
            }
        }
    }

    private func handleEnvelope(
        _ envelope: RelayEnvelope,
        deviceToken: String
    ) async throws {
        // Drop+ack on malformed envelopes — the previous `return` path
        // left the envelope on the server forever and let a hostile
        // peer mint unlimited null-sender blobs to flood the inbox
        // (DoS, shared P0 with Android from the polling security
        // review).
        guard let senderDeviceId = envelope.senderDeviceId else {
            logger.warning("envelope missing senderDeviceId — ack + drop")
            await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
            return
        }
        guard let senderAccountId = envelope.senderAccountId else {
            logger.warning("envelope missing senderAccountId — ack + drop")
            await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
            return
        }

        guard let ciphertextBytes = Data(base64Encoded: envelope.blob), !ciphertextBytes.isEmpty else {
            logger.warning("empty/malformed ciphertext — ack + drop")
            await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
            return
        }
        // Signal's type byte is the lower nibble of the first byte of
        // the serialised CiphertextMessage. Mirror of Android
        // `typeByte and 0x0F`. Values: 2 = Whisper, 3 = PreKey.
        let typeByte = Int(ciphertextBytes[0]) & 0x0F
        let preKeyType = 3
        let whisperType = 2

        let store = try SignalIdentityKeys.protocolStore()
        let senderAddress = try ProtocolAddress(
            name: senderAccountId,
            deviceId: RemoteChatRepository.defaultDeviceIndex
        )

        // Pre-decrypt: capture the sender's identity key from the
        // PreKeySignalMessage header BEFORE decrypt consumes the
        // message. TOFU pin on inbound-first contact (review P0 #2).
        let plaintext: Data
        var peerIdentityKeyB64: String?
        switch typeByte {
        case preKeyType:
            let preKeyMessage = try PreKeySignalMessage(bytes: ciphertextBytes)
            // Serialise the FULL IdentityKey (incl. type-tag) so the
            // pinned string is byte-identical to what the peer's
            // `fetchPreKey` response carried and what the outbound
            // `buildSession` TOFU check compares against. Using
            // `identityKey.publicKey.serialize()` drops the tag and
            // makes every inbound-first-contact reply raise a false
            // `safetyNumberMismatch` (P0 #2 from the E2E iOS review).
            peerIdentityKeyB64 = preKeyMessage.identityKey.serialize().base64EncodedString()

            plaintext = try signalDecryptPreKey(
                message: preKeyMessage,
                from: senderAddress,
                sessionStore: store,
                identityStore: store,
                preKeyStore: store,
                signedPreKeyStore: store,
                kyberPreKeyStore: store,
                context: NullContext()
            )

        case whisperType:
            let signalMessage = try SignalMessage(bytes: ciphertextBytes)
            plaintext = try signalDecrypt(
                message: signalMessage,
                from: senderAddress,
                sessionStore: store,
                identityStore: store,
                context: NullContext()
            )

        default:
            logger.warning("unknown ciphertext type \(typeByte, privacy: .public) — ack + drop")
            await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
            return
        }

        let body = String(data: plaintext, encoding: .utf8) ?? ""

        let conversationId = try await resolveOrCreateConversation(
            senderAccountId: senderAccountId,
            senderDeviceId: senderDeviceId,
            peerIdentityKeyB64: peerIdentityKeyB64
        )
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        try await messageDao.insert(MessageEntity(
            id: envelope.messageId,
            conversationId: conversationId,
            senderDeviceId: senderDeviceId,
            body: body,
            timestamp: now,
            isOutbound: false,
            deliveryState: DeliveryState.delivered
        ))
        try await conversationDao.updateLastMessage(
            conversationId: conversationId,
            messageId: envelope.messageId,
            preview: String(body.prefix(Self.previewMaxLen)),
            at: now
        )
        try await conversationDao.incrementUnread(conversationId: conversationId)

        // Successful decrypt → clear the failure counter so a future
        // unrelated envelope doesn't inherit the wrong count.
        await resetFailureCounter(for: envelope.messageId)
        await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
    }

    private func ackEnvelope(messageId: String, deviceToken: String) async {
        do {
            try await relayClient.deleteMessage(
                deviceToken: deviceToken,
                messageId: messageId
            )
        } catch {
            logger.warning("ack network failure — will replay: \(type(of: error), privacy: .public)")
        }
    }

    // MARK: - Conversation resolve

    /// Find a conversation for the sender, or create a new one. On
    /// first contact we pin the peer's identityKey extracted from the
    /// PreKeySignalMessage so the next outbound-reply's TOFU check
    /// has a real value to compare against.
    ///
    /// Throws `AppError.safetyNumberMismatch` when the envelope
    /// carries an identityKey that contradicts the pinned one, or is
    /// already bound to a different accountId — either is a strong
    /// signal of MITM / sender spoofing. The outer poll loop treats
    /// this as a decrypt failure and the dead-letter counter
    /// eventually ack+drops the envelope (mirror of Android
    /// `IdentityChangedException`).
    private func resolveOrCreateConversation(
        senderAccountId: String,
        senderDeviceId: String,
        peerIdentityKeyB64: String?
    ) async throws -> String {
        try await resolveLock.withLock {
            try await self.resolveOrCreateConversationLocked(
                senderAccountId: senderAccountId,
                senderDeviceId: senderDeviceId,
                peerIdentityKeyB64: peerIdentityKeyB64
            )
        }
    }

    private func resolveOrCreateConversationLocked(
        senderAccountId: String,
        senderDeviceId: String,
        peerIdentityKeyB64: String?
    ) async throws -> String {
        if let existing = try await conversationDao.findByPeerAccountId(senderAccountId) {
            // Second + inbound message: the identity key is already
            // pinned. If a fresh PreKeySignalMessage carries a new
            // identity key, refuse — let the envelope dead-letter so
            // the UI can surface a "safety number changed" error
            // once it lands.
            if let fresh = peerIdentityKeyB64,
               !existing.peerIdentityKey.isEmpty,
               existing.peerIdentityKey != fresh {
                logger.error("peer identity changed for conv \(existing.id, privacy: .private) — refusing")
                throw AppError.safetyNumberMismatch
            }
            return existing.id
        }

        // First contact from this peer. WHISPER for a brand-new peer
        // is technically impossible (a Whisper message needs a
        // pre-existing session), so a null pin is a poison envelope —
        // let it dead-letter.
        guard let pinned = peerIdentityKeyB64, !pinned.isEmpty else {
            logger.error("WHISPER first-contact for unknown peer — refusing")
            throw AppError.safetyNumberMismatch
        }

        // Sender-spoofing defense: if ANOTHER accountId already has
        // this identity key pinned, a hostile relay is forwarding
        // someone else's ciphertext under this accountId. Libsignal
        // would happily decrypt (the ratchet matches the real peer)
        // and we'd render the message attributed to the wrong
        // identity. Refuse and dead-letter (mirror of Android spoof
        // defense).
        if let collision = try await conversationDao.findByIdentityKeyExcluding(
            peerIdentityKey: pinned,
            excludeAccountId: senderAccountId
        ) {
            logger.error("identity already bound to \(collision.id, privacy: .private) — spoof")
            throw AppError.safetyNumberMismatch
        }

        let conversationId = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let entity = ConversationEntity(
            id: conversationId,
            peerAccountId: senderAccountId,
            peerUsername: nil,
            peerDisplayName: nil,
            peerDeviceId: senderDeviceId,
            peerRegistrationId: 0,
            peerIdentityKey: pinned,
            lastMessageAt: 0,
            unreadCount: 0,
            createdAt: now,
            updatedAt: now
        )
        try await conversationDao.insert(entity)

        // Best-effort discovery back-fill (review P0 #6) — resolve the
        // peer's username so the conversation list shows a real handle
        // rather than the opaque accountId. Failure is silent; the UI
        // falls back to peerAccountId.
        Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.discoveryClient.searchByUsername(senderAccountId)
                if let username = user.username {
                    try? await self.conversationDao.updatePeerUsername(
                        conversationId: conversationId,
                        peerUsername: username
                    )
                }
            } catch {
                // swallow — discovery is best-effort
            }
        }

        return conversationId
    }

    // MARK: - Failure counter helpers (persisted in SQLCipher)

    /// Atomic UPSERT-and-read via `DeadLetterDao.bump`. The counter
    /// survives cold starts now — a hostile relay that waits for the
    /// app to kill/restart can't reset the counter back to zero and
    /// loop the same poison envelope indefinitely (P1 from the
    /// cross-platform polling security review).
    private func bumpFailureCounter(for messageId: String) async -> Int {
        do {
            return try await deadLetterDao.bump(
                messageId: messageId,
                now: Int64(Date().timeIntervalSince1970 * 1000)
            )
        } catch {
            // Counter write failed — fall back to in-memory so we
            // still eventually dead-letter within the current process.
            logger.warning("dead-letter bump failed: \(type(of: error), privacy: .public)")
            return counterQueue.sync {
                let next = (decryptFailureCounts[messageId] ?? 0) + 1
                decryptFailureCounts[messageId] = next
                return next
            }
        }
    }

    private func resetFailureCounter(for messageId: String) async {
        try? await deadLetterDao.reset(messageId: messageId)
        counterQueue.sync {
            decryptFailureCounts.removeValue(forKey: messageId)
        }
    }

}
