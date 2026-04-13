// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB

/// iOS twin of `MessageDao.kt` — message-row SQL entry points.
struct MessageDao {
    let writer: any DatabaseWriter

    // MARK: - Reads

    func observeForConversation(_ conversationId: String) -> AsyncStream<[MessageEntity]> {
        let observation = ValueObservation.tracking { db in
            try MessageEntity
                .filter(MessageEntity.Columns.conversationId == conversationId)
                .order(MessageEntity.Columns.timestamp.asc)
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

    func findById(_ id: String) async throws -> MessageEntity? {
        try await writer.read { db in
            try MessageEntity.fetchOne(db, key: id)
        }
    }

    // MARK: - Writes

    /// `@Insert(onConflict = OnConflictStrategy.IGNORE)` twin — a
    /// replay of a successful inbound insert (after a crash between
    /// insert and ack) is a no-op.
    func insert(_ message: MessageEntity) async throws {
        try await writer.write { db in
            try message.insert(db, onConflict: .ignore)
        }
    }

    func updateDeliveryState(id: String, state: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE messages SET deliveryState = ? WHERE id = ?",
                arguments: [state, id]
            )
        }
    }

    func deleteById(_ id: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM messages WHERE id = ?",
                arguments: [id]
            )
        }
    }
}
