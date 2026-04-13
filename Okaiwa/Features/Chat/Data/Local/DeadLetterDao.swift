// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB

/// Persisted replacement for the in-memory decrypt-failure counter
/// that the polling service used to keep in a `[String: Int]`. Backed
/// by the SQLCipher-encrypted `dead_letter_counts` table so the
/// counter survives cold starts — a hostile relay that minted a
/// poison envelope could previously cycle `MAX_DECRYPT_RETRIES - 1`
/// failed attempts, wait for the user to background the app, and
/// loop the same envelope indefinitely (P1 from the cross-platform
/// polling security review, mirror of Android's `DeadLetterDao`).
///
/// Operations are intentionally minimal: `bump` (atomic UPSERT that
/// returns the new value) and `reset` (DELETE). No reads outside of
/// these two, and the table is pruned on signOut.
struct DeadLetterDao {
    let writer: any DatabaseWriter

    /// Atomically increment the counter for a messageId and return
    /// the post-increment value. Uses `INSERT ... ON CONFLICT DO
    /// UPDATE` so the read-modify-write is a single SQL statement —
    /// no TOCTOU window where two concurrent bumps could land the
    /// same value twice.
    func bump(messageId: String, now: Int64) async throws -> Int {
        try await writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO dead_letter_counts (messageId, count, updatedAt)
                VALUES (?, 1, ?)
                ON CONFLICT(messageId) DO UPDATE SET
                    count = count + 1,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [messageId, now]
            )
            let value = try Int.fetchOne(
                db,
                sql: "SELECT count FROM dead_letter_counts WHERE messageId = ?",
                arguments: [messageId]
            ) ?? 0
            return value
        }
    }

    func reset(messageId: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM dead_letter_counts WHERE messageId = ?",
                arguments: [messageId]
            )
        }
    }
}
