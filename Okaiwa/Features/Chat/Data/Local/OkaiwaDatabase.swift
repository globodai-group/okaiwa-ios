// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB
import os

/// Main application database — iOS twin of `OkaiwaDatabase.kt`.
///
/// Encryption-at-rest:
///   - Backed by SQLCipher 4.x, bundled inside the DuckDuckGo fork of
///     GRDB.swift (see `Package.swift` for why this fork).
///   - Passphrase is a 32-byte CSPRNG blob generated on first launch
///     and stashed in the iOS Keychain with
///     `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — the
///     `KeychainManager` wrapper sets that attribute on every save.
///   - We NEVER derive the passphrase from `SessionStore.accessToken`.
///     The access token rotates on refresh and the database can't
///     follow; the passphrase is bound to the app install and outlives
///     every session.
///
/// NO plaintext writes happen outside this path — the session blob
/// already lives behind the Keychain, and message bodies are AES-256
/// page-encrypted here.
final class OkaiwaDatabase: @unchecked Sendable {
    /// Singleton — the chat repository and the polling service both
    /// resolve the same queue so ValueObservation replays land in the
    /// right transaction scope.
    static let shared: OkaiwaDatabase = {
        do {
            return try OkaiwaDatabase()
        } catch {
            // Fatal — if we can't open the encrypted DB on launch,
            // the chat layer can't function. Better to crash loudly
            // than to silently fall back to an unencrypted store.
            fatalError("OkaiwaDatabase init failed: \(error)")
        }
    }()

    let writer: any DatabaseWriter

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "OkaiwaDatabase")

    private init(keychain: KeychainManager = KeychainManager()) throws {
        let passphrase = try Self.loadOrGeneratePassphrase(keychain: keychain)

        // GRDB + SQLCipher: we pass the passphrase via the
        // `usePassphrase` configuration hook. The DuckDuckGo fork's
        // `Configuration` exposes a `prepareDatabase` hook where we
        // can run `PRAGMA key`; we use the higher-level helper here
        // to keep the integration simple. See
        // https://github.com/duckduckgo/GRDB.swift and
        // Documentation/SQLCipher.md on upstream for details.
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.usePassphrase(passphrase)
        }

        let databaseURL = try Self.databaseFileURL()
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)

        try Self.migrator.migrate(queue)
        self.writer = queue
        logger.info("OkaiwaDatabase opened at \(databaseURL.lastPathComponent, privacy: .public)")
    }

    // MARK: - Convenience accessors

    var conversationDao: ConversationDao {
        ConversationDao(writer: writer)
    }

    var messageDao: MessageDao {
        MessageDao(writer: writer)
    }

    /// Persisted dead-letter counter — see `dead_letter_counts` in
    /// the v2 migration. Survives cold starts so a hostile relay
    /// can't reset the counter by crashing the app.
    var deadLetterDao: DeadLetterDao {
        DeadLetterDao(writer: writer)
    }

    /// Wipe every row in every messaging table. Called from
    /// `IdentityAuthService.signOut` — the next account on the same
    /// device MUST NOT inherit the previous user's conversations or
    /// message bodies (cross-account leak P1 from the polling
    /// security review, mirror of Android `Room.clearAllTables`).
    ///
    /// Uses DELETE rather than DROP so the schema stays intact and
    /// the next login can reuse the connection without re-running the
    /// migrator. Runs inside a single transaction so a concurrent
    /// ValueObservation never sees a half-emptied view.
    func wipeAllMessagingData() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM messages")
            try db.execute(sql: "DELETE FROM conversations")
            try db.execute(sql: "DELETE FROM dead_letter_counts")
        }
    }

    // MARK: - Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // v1 — baseline schema. Indexes mirror the Android Room
        // entity exactly so cross-device backup/restore (still a
        // distant TODO) can re-use the same layout.
        migrator.registerMigration("v1_baseline") { db in
            try db.create(table: "conversations") { t in
                t.column("id", .text).primaryKey()
                t.column("peerAccountId", .text).notNull().unique()
                t.column("peerUsername", .text)
                t.column("peerDisplayName", .text)
                t.column("peerDeviceId", .text).notNull().indexed()
                t.column("peerRegistrationId", .integer).notNull().defaults(to: 0)
                t.column("peerIdentityKey", .text).notNull().defaults(to: "")
                t.column("lastMessageId", .text)
                t.column("lastMessagePreview", .text)
                t.column("lastMessageAt", .integer).notNull().defaults(to: 0).indexed()
                t.column("unreadCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
            }

            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("conversationId", .text).notNull()
                t.column("senderDeviceId", .text).notNull()
                t.column("body", .text).notNull()
                t.column("timestamp", .integer).notNull()
                t.column("isOutbound", .boolean).notNull()
                t.column("deliveryState", .text).notNull()
            }
            try db.create(
                index: "idx_messages_conversation_timestamp",
                on: "messages",
                columns: ["conversationId", "timestamp"]
            )
            try db.create(
                index: "idx_messages_deliveryState",
                on: "messages",
                columns: ["deliveryState"]
            )
        }

        // v2 — persisted dead-letter counter table.
        //
        // The in-memory ConcurrentHashMap on Android and [String:Int]
        // on iOS reset on every app launch, so a hostile relay could
        // cycle through MAX_DECRYPT_RETRIES-1 attempts, wait for the
        // user to kill the app, and loop the same poison envelope
        // indefinitely (P1 from the cross-platform polling security
        // review). Persisting the counter inside the already-
        // encrypted SQLCipher DB means the counter survives cold
        // starts and the dead-letter ceiling is actually enforced.
        migrator.registerMigration("v2_dead_letter_counts") { db in
            try db.create(table: "dead_letter_counts") { t in
                t.column("messageId", .text).primaryKey()
                t.column("count", .integer).notNull().defaults(to: 0)
                t.column("updatedAt", .integer).notNull()
            }
        }

        return migrator
    }

    // MARK: - Paths

    private static func databaseFileURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("okaiwa-db", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        // Application Support is NOT excluded from backups by default —
        // the encrypted DB has to opt out so an iTunes / iCloud restore
        // never exfiltrates message history to a different device.
        // Keychain + SQLCipher are both device-bound; backups would
        // reintroduce the surface we just closed.
        //
        // Re-applied on EVERY call (idempotent): an app upgraded from a
        // pre-exclusion build has the directory on disk without the
        // flag, and a first-creation-only check would silently leak
        // history to iCloud on that install (P0 #3 from the iOS review).
        var mutableURL = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)
        return directory.appendingPathComponent("okaiwa.sqlite")
    }

    // MARK: - Passphrase

    private enum PassphraseKey {
        static let keychain = "io.okaiwa.db.passphrase.v1"
        static let bytes = 32
    }

    private static func loadOrGeneratePassphrase(
        keychain: KeychainManager
    ) throws -> Data {
        if let existing = try keychain.load(forKey: PassphraseKey.keychain), existing.count == PassphraseKey.bytes {
            return existing
        }
        var fresh = Data(count: PassphraseKey.bytes)
        let status = fresh.withUnsafeMutableBytes { bytes -> Int32 in
            guard let base = bytes.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, PassphraseKey.bytes, base)
        }
        guard status == errSecSuccess else {
            throw AppError.keyError(reason: "CSPRNG failure for DB passphrase: \(status)")
        }
        try keychain.save(data: fresh, forKey: PassphraseKey.keychain)
        return fresh
    }
}
