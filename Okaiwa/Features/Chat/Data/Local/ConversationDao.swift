// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB

/// iOS twin of `ConversationDao.kt` — thin SQL layer that the chat
/// repository and the polling service talk to.
///
/// GRDB's `ValueObservation` gives us a Kotlin-`Flow`-equivalent
/// publisher surface via `AsyncValueObservation`; we expose it as an
/// `AsyncStream` so the repository doesn't leak GRDB types to its
/// callers.
///
/// Every method here does one thing and takes the passed-in
/// `DatabaseReader` / `DatabaseWriter` — no hidden singletons. The
/// `OkaiwaDatabase.shared` reference is the one production call site.
struct ConversationDao {
    let writer: any DatabaseWriter

    // MARK: - Reads

    func observeAll() -> AsyncStream<[ConversationEntity]> {
        // `ORDER BY lastMessageAt DESC, updatedAt DESC` — mirrors the
        // Android `observeAll` ORDER BY exactly so the conversation
        // list rows land in the same sequence on both platforms.
        let observation = ValueObservation.tracking { db in
            try ConversationEntity
                .order(
                    ConversationEntity.Columns.lastMessageAt.desc,
                    ConversationEntity.Columns.updatedAt.desc
                )
                .fetchAll(db)
        }

        return AsyncStream { continuation in
            let cancellable = observation.start(
                in: writer,
                onError: { _ in continuation.finish() },
                onChange: { rows in continuation.yield(rows) }
            )
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    func findById(_ id: String) async throws -> ConversationEntity? {
        try await writer.read { db in
            try ConversationEntity.fetchOne(db, key: id)
        }
    }

    func findByPeerAccountId(_ peerAccountId: String) async throws -> ConversationEntity? {
        try await writer.read { db in
            try ConversationEntity
                .filter(ConversationEntity.Columns.peerAccountId == peerAccountId)
                .fetchOne(db)
        }
    }

    func findByPeerDeviceId(_ peerDeviceId: String) async throws -> ConversationEntity? {
        try await writer.read { db in
            try ConversationEntity
                .filter(ConversationEntity.Columns.peerDeviceId == peerDeviceId)
                .fetchOne(db)
        }
    }

    // MARK: - Writes

    /// Room's `@Insert(onConflict = OnConflictStrategy.IGNORE)`
    /// equivalent. GRDB doesn't have a built-in IGNORE mode on
    /// `insert`, so we use the ON CONFLICT IGNORE clause via
    /// `insert(db, onConflict: .ignore)` (the `DatabaseConflictPolicy`
    /// path). Matches Android's idempotent-insert semantics exactly —
    /// a replay of an inbound message with the same primary key is a
    /// no-op rather than a crash.
    func insert(_ conversation: ConversationEntity) async throws {
        try await writer.write { db in
            try conversation.insert(db, onConflict: .ignore)
        }
    }

    func updateLastMessage(
        conversationId: String,
        messageId: String,
        preview: String,
        at: Int64
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE conversations
                   SET lastMessageId = ?,
                       lastMessagePreview = ?,
                       lastMessageAt = ?,
                       updatedAt = ?
                 WHERE id = ?
                """,
                arguments: [messageId, preview, at, at, conversationId]
            )
        }
    }

    func clearUnread(conversationId: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE conversations SET unreadCount = 0 WHERE id = ?",
                arguments: [conversationId]
            )
        }
    }

    /// Pin or update the peer's Signal identity key. Called from
    /// `RemoteChatRepository.buildSession` on first contact (TOFU
    /// commit) and from the polling service on first inbound
    /// PreKeySignalMessage.
    ///
    /// NEVER call this to overwrite an existing non-empty
    /// `peerIdentityKey` without the user's explicit confirmation —
    /// silent overwrite is exactly the MITM hole TOFU exists to
    /// close. The caller must do the isNotEmpty check before
    /// invoking this method.
    func updatePeerIdentity(
        conversationId: String,
        peerIdentityKey: String,
        peerRegistrationId: Int
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                UPDATE conversations
                   SET peerIdentityKey = ?,
                       peerRegistrationId = ?
                 WHERE id = ?
                """,
                arguments: [peerIdentityKey, peerRegistrationId, conversationId]
            )
        }
    }

    /// Update the human-readable peer name after the receiver resolves
    /// it via discovery on first inbound contact.
    func updatePeerUsername(conversationId: String, peerUsername: String?) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE conversations SET peerUsername = ? WHERE id = ?",
                arguments: [peerUsername, conversationId]
            )
        }
    }

    func incrementUnread(conversationId: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE conversations SET unreadCount = unreadCount + 1 WHERE id = ?",
                arguments: [conversationId]
            )
        }
    }
}
