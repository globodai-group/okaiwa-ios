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

    private var pollingTask: Task<Void, Never>?

    public init(
        database: OkaiwaDatabase = .shared,
        relayClient: RelayAPIClient = RelayAPIClient(),
        discoveryClient: DiscoveryAPIClient = DiscoveryAPIClient(),
        sessionProvider: (@Sendable () async -> SessionStore.Session?)? = nil
    ) {
        self.conversationDao = database.conversationDao
        self.messageDao = database.messageDao
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
                resetFailureCounter(for: envelope.messageId)
            } catch {
                let next = bumpFailureCounter(for: envelope.messageId)
                if next >= Self.maxDecryptRetries {
                    logger.warning(
                        "envelope dead-lettered after \(next, privacy: .public) attempts — ack + drop"
                    )
                    await ackEnvelope(messageId: envelope.messageId, deviceToken: deviceToken)
                    resetFailureCounter(for: envelope.messageId)
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
        guard let senderDeviceId = envelope.senderDeviceId else {
            logger.warning("envelope missing senderDeviceId — skip")
            return
        }
        guard let senderAccountId = envelope.senderAccountId else {
            // Mirror of Android behavior — log and skip. At-least-once
            // will redeliver once the backend catches up.
            logger.warning("envelope missing senderAccountId — skip (backend gap)")
            return
        }

        guard let ciphertextBytes = Data(base64Encoded: envelope.blob), !ciphertextBytes.isEmpty else {
            logger.warning("empty/malformed ciphertext — skip")
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
            logger.warning("unknown ciphertext type \(typeByte, privacy: .public) — skip")
            return
        }

        let body = String(data: plaintext, encoding: .utf8) ?? ""

        let conversationId = try await resolveOrCreateConversation(
            senderAccountId: senderAccountId,
            senderDeviceId: senderDeviceId,
            peerIdentityKeyB64: peerIdentityKeyB64
        )
        guard !conversationId.isEmpty else {
            // Whisper first-contact for an unknown peer — impossible
            // under normal flow. Skipped by `resolveOrCreateConversation`.
            return
        }
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
        resetFailureCounter(for: envelope.messageId)
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
    /// has a real value to compare against (was empty string in the
    /// pre-iteration implementation, which silently accepted any key
    /// swap — review P0 #2).
    private func resolveOrCreateConversation(
        senderAccountId: String,
        senderDeviceId: String,
        peerIdentityKeyB64: String?
    ) async throws -> String {
        if let existing = try await conversationDao.findByPeerAccountId(senderAccountId) {
            // Second + inbound message: the identity key is already
            // pinned. If a fresh PreKeySignalMessage carries a new
            // identity key, refuse silently — the bubble surfaces a
            // "safety number changed" error once that UI lands.
            if let fresh = peerIdentityKeyB64,
               !existing.peerIdentityKey.isEmpty,
               existing.peerIdentityKey != fresh {
                logger.warning("peer identity changed — refusing to pin silently")
            }
            return existing.id
        }

        // First contact from this peer.
        let conversationId = UUID().uuidString
        guard let pinned = peerIdentityKeyB64, !pinned.isEmpty else {
            // WHISPER_TYPE for a brand-new peer is technically
            // impossible (a Whisper message needs a pre-existing
            // session). If it happens, log + skip via empty return.
            logger.warning("WHISPER first-contact for new peer — skip envelope")
            return ""
        }
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

    // MARK: - Failure counter helpers (thread-safe)

    private func bumpFailureCounter(for messageId: String) -> Int {
        counterQueue.sync {
            let next = (decryptFailureCounts[messageId] ?? 0) + 1
            decryptFailureCounts[messageId] = next
            return next
        }
    }

    private func resetFailureCounter(for messageId: String) {
        counterQueue.sync {
            decryptFailureCounts.removeValue(forKey: messageId)
        }
    }

}
