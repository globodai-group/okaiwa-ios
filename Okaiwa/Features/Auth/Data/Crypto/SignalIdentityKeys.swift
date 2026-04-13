// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import LibSignalClient
import os

/// Real Signal Protocol identity material — iOS twin of
/// `SignalIdentityKeys.kt`. This module is the single source of truth
/// for the on-device keypair + signed pre-key + one-time pre-key pool +
/// kyber (PQXDH) pre-key that the backend stores and that peers
/// encapsulate against.
///
/// Material generated on first launch:
///   - 1 IdentityKeyPair (Curve25519) — the long-term device identity.
///   - 1 SignedPreKeyRecord — signed by the identity private key.
///   - `SignalIdentityKeys.oneTimePreKeyCount` one-time pre-keys
///     (default 100) — consumed by peers one per session init.
///   - 1 KyberPreKeyRecord — ML-KEM-1024, signed by the identity
///     private key. libsignal 0.92 requires a kyber in every bundle.
///   - 1 14-bit registrationId.
///
/// Persistence: every field above is serialised and stashed in the
/// iOS Keychain via `SignalIdentityPersistence`. Across an app
/// restart `loadOrGenerate()` rehydrates the same keys; peers who
/// have cached a PreKeyBundle keyed on our identity can still drive
/// `SessionBuilder.process(bundle)` against us.
///
/// Critical fix (review P0 mirror of Android's dc897f1):
///   - On rehydrate, if the persisted snapshot has NO kyber record
///     (pre-commit user), we mint one lazily AND reset
///     `preKeysUploaded = false` so the next `ensurePreKeysUploaded()`
///     actually pushes the kyber to the server. Without that reset,
///     peers fetching the pre-commit user's bundle get
///     `kyberPreKey: null` → SessionBuilder.process throws → messages
///     never reach them.
///
/// Thread safety: `SignalStore` serialises every access through a
/// single dispatch queue (existing file, not touched here). The
/// `loadOrGenerate` side of this type is protected by its own
/// dispatch-queue barrier so two cold launches don't both generate a
/// store and race the keychain write.
enum SignalIdentityKeys {

    // MARK: - Wire format (matches okaiwa-server validators)

    /// Base64-encoded signed pre-key, one-to-one with the Android
    /// `SignedPreKeyDto` and the backend Vine schema.
    struct SignedPreKey: Codable, Equatable, Sendable {
        let keyId: Int
        let publicKey: String
        let signature: String
    }

    /// Payload shipped to `/v1/auth/register`. Callers forward it to
    /// `IdentityAuthClient`.
    struct Bundle: Equatable, Sendable {
        let identityPublicKey: String
        let signedPreKey: SignedPreKey
        let registrationId: Int
    }

    /// Snapshot handed to the PreKey upload request — mirror of
    /// `SignalIdentityKeys.UploadBatch` on Android.
    struct UploadBatch: Equatable, Sendable {
        struct PreKeyPublic: Equatable, Sendable {
            let keyId: Int
            let publicKey: String
        }
        /// Max 100 rows. `publicKey` is base64 of the PreKeyRecord's
        /// public ECPublicKey.
        let oneTimePreKeys: [PreKeyPublic]
        /// Signed pre-key already sent at register time — re-uploaded
        /// here so the relay has a fresh record even for accounts
        /// that verified against an older revision of
        /// `/v1/auth/register`.
        let signedPreKey: SignedPreKey
        let kyberPreKey: KyberPreKeyDto
        let identityPublicKey: String
        let registrationId: Int
    }

    // MARK: - Constants (mirror of SignalIdentityKeys.Companion on Android)

    /// Size of the one-time pre-key pool generated at first launch.
    static let oneTimePreKeyCount: Int = 100
    /// Initial signed pre-key id — rotated by the (still-unimplemented)
    /// periodic rotation job.
    static let signedPreKeyInitialId: UInt32 = 1
    /// Initial Kyber (PQXDH) pre-key id.
    static let kyberPreKeyInitialId: UInt32 = 1

    private static let logger = Logger(
        subsystem: "io.okaiwa.app",
        category: "SignalIdentityKeys"
    )
    private static let loadQueue = DispatchQueue(label: "io.okaiwa.signal.keys.load")

    // MARK: - Generation / rehydration

    /// Idempotent entry point. On first launch, generates a fresh key
    /// bundle and writes it to the Keychain. On subsequent launches
    /// rehydrates from the persisted snapshot.
    ///
    /// Returns the same `InMemorySignalProtocolStore` installed by
    /// `SignalStore.shared.configure(...)` — the chat repository
    /// reads it via `protocolStore()` to drive SessionBuilder /
    /// SessionCipher.
    @discardableResult
    static func loadOrGenerate(
        persistence: SignalIdentityPersistence = .shared
    ) throws -> InMemorySignalProtocolStore {
        try loadQueue.sync {
            if let cached = SignalStore.shared.cached() {
                return cached
            }

            if let persisted = try persistence.read() {
                return try rehydrate(persisted: persisted, persistence: persistence)
            }
            return try generateFresh(persistence: persistence)
        }
    }

    /// Build the registration bundle `/v1/auth/register` expects. Runs
    /// `loadOrGenerate` so the bundle is always backed by the same
    /// keys the chat layer will sign / decrypt with.
    static func registrationBundle(
        persistence: SignalIdentityPersistence = .shared
    ) throws -> Bundle {
        _ = try loadOrGenerate(persistence: persistence)
        guard let snapshot = try persistence.read() else {
            throw AppError.keyError(reason: "Identity snapshot missing after loadOrGenerate")
        }

        let signed = try SignedPreKeyRecord(bytes: snapshot.signedPreKeyRecord)

        return Bundle(
            identityPublicKey: snapshot.identityPublicKey.base64EncodedString(),
            signedPreKey: SignedPreKey(
                keyId: Int(signed.id),
                publicKey: try signed.publicKey().serialize().base64EncodedString(),
                signature: signed.signature.base64EncodedString()
            ),
            registrationId: Int(snapshot.registrationId)
        )
    }

    /// Snapshot of the upload payload — the one-time pre-key pool
    /// plus signed pre-key plus kyber pre-key. Idempotent: the
    /// `arePreKeysUploaded()` flag gates re-uploads across cold
    /// starts, so this helper just builds the payload — the caller
    /// decides whether to send.
    static func uploadBatch(
        persistence: SignalIdentityPersistence = .shared
    ) throws -> UploadBatch {
        _ = try loadOrGenerate(persistence: persistence)
        guard let snapshot = try persistence.read() else {
            throw AppError.keyError(reason: "Identity snapshot missing after loadOrGenerate")
        }
        guard let kyberRaw = snapshot.kyberPreKeyRecord, snapshot.kyberPreKeyId > 0 else {
            throw AppError.keyError(
                reason: "Kyber pre-key record missing — regenerate before upload"
            )
        }

        let signed = try SignedPreKeyRecord(bytes: snapshot.signedPreKeyRecord)
        let kyber = try KyberPreKeyRecord(bytes: kyberRaw)

        let oneTime: [UploadBatch.PreKeyPublic] = try snapshot.oneTimePreKeyRecords.compactMap { raw in
            let record = try PreKeyRecord(bytes: raw)
            let pub = try record.publicKey().serialize()
            return UploadBatch.PreKeyPublic(
                keyId: Int(record.id),
                publicKey: pub.base64EncodedString()
            )
        }

        return UploadBatch(
            oneTimePreKeys: oneTime,
            signedPreKey: SignedPreKey(
                keyId: Int(signed.id),
                publicKey: try signed.publicKey().serialize().base64EncodedString(),
                signature: signed.signature.base64EncodedString()
            ),
            kyberPreKey: KyberPreKeyDto(
                keyId: Int(kyber.id),
                publicKey: try kyber.keyPair().publicKey.serialize().base64EncodedString(),
                signature: kyber.signature.base64EncodedString()
            ),
            identityPublicKey: snapshot.identityPublicKey.base64EncodedString(),
            registrationId: Int(snapshot.registrationId)
        )
    }

    static func markPreKeysUploaded(
        persistence: SignalIdentityPersistence = .shared
    ) throws {
        try persistence.markPreKeysUploaded()
    }

    static func arePreKeysUploaded(
        persistence: SignalIdentityPersistence = .shared
    ) -> Bool {
        (try? persistence.read())?.preKeysUploaded == true
    }

    /// Expose the protocol store so the chat layer can hand it to
    /// libsignal's session APIs. Matches `SignalIdentityKeys.protocolStore()`
    /// on Android — ensures the store is populated before handing it
    /// out.
    static func protocolStore(
        persistence: SignalIdentityPersistence = .shared
    ) throws -> InMemorySignalProtocolStore {
        try loadOrGenerate(persistence: persistence)
    }

    // MARK: - Internal — fresh generation

    private static func generateFresh(
        persistence: SignalIdentityPersistence
    ) throws -> InMemorySignalProtocolStore {
        let identity = IdentityKeyPair.generate()
        let registrationId = UInt32.random(in: 1..<0x4000)

        // Signed pre-key — real signature over the public bytes.
        let signedPrivate = PrivateKey.generate()
        let signedPublic = signedPrivate.publicKey
        let signedTimestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let signedSignature = identity.privateKey.generateSignature(
            message: signedPublic.serialize()
        )
        let signedRecord = try SignedPreKeyRecord(
            id: signedPreKeyInitialId,
            timestamp: signedTimestamp,
            privateKey: signedPrivate,
            signature: signedSignature
        )

        // One-time pre-keys. Ids start at 1 (0 is reserved as
        // "no pre-key" by some peers).
        var oneTimeRecords: [PreKeyRecord] = []
        for id in 1...oneTimePreKeyCount {
            let pk = PrivateKey.generate()
            let record = try PreKeyRecord(id: UInt32(id), privateKey: pk)
            oneTimeRecords.append(record)
        }

        // Kyber (ML-KEM-1024) pre-key — libsignal 0.92 exposes
        // KEMKeyPair.generate() which defaults to Kyber-1024.
        let kyberPair = KEMKeyPair.generate()
        let kyberSignature = identity.privateKey.generateSignature(
            message: kyberPair.publicKey.serialize()
        )
        let kyberRecord = try KyberPreKeyRecord(
            id: kyberPreKeyInitialId,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            keyPair: kyberPair,
            signature: kyberSignature
        )

        // Install into the shared store and persist the snapshot.
        let store = try SignalStore.shared.configure(
            identity: identity,
            registrationId: registrationId
        )
        try store.storeSignedPreKey(signedRecord, id: signedPreKeyInitialId, context: NullContext())
        for record in oneTimeRecords {
            try store.storePreKey(record, id: record.id, context: NullContext())
        }
        try store.storeKyberPreKey(kyberRecord, id: kyberPreKeyInitialId, context: NullContext())

        try persistence.write(Snapshot(
            identityKeyPair: identity.serialize(),
            identityPublicKey: identity.publicKey.serialize(),
            registrationId: registrationId,
            signedPreKeyId: signedPreKeyInitialId,
            signedPreKeyRecord: signedRecord.serialize(),
            oneTimePreKeyRecords: oneTimeRecords.map { $0.serialize() },
            kyberPreKeyRecord: kyberRecord.serialize(),
            kyberPreKeyId: kyberPreKeyInitialId,
            preKeysUploaded: false
        ))
        logger.info("Fresh Signal identity generated (registrationId=\(registrationId, privacy: .public))")
        return store
    }

    // MARK: - Internal — rehydrate from disk

    private static func rehydrate(
        persisted: Snapshot,
        persistence: SignalIdentityPersistence
    ) throws -> InMemorySignalProtocolStore {
        let identity = try IdentityKeyPair(bytes: persisted.identityKeyPair)
        let store = try SignalStore.shared.configure(
            identity: identity,
            registrationId: persisted.registrationId
        )

        let signed = try SignedPreKeyRecord(bytes: persisted.signedPreKeyRecord)
        try store.storeSignedPreKey(signed, id: persisted.signedPreKeyId, context: NullContext())

        for raw in persisted.oneTimePreKeyRecords {
            let record = try PreKeyRecord(bytes: raw)
            try store.storePreKey(record, id: record.id, context: NullContext())
        }

        if let kyberRaw = persisted.kyberPreKeyRecord, persisted.kyberPreKeyId > 0 {
            let kyber = try KyberPreKeyRecord(bytes: kyberRaw)
            try store.storeKyberPreKey(kyber, id: persisted.kyberPreKeyId, context: NullContext())
        }

        // ────────────────────────────────────────────────────────────
        // Back-fill path (mirror of Android P0 fix in dc897f1).
        //
        // Accounts that were registered BEFORE the kyber plumbing
        // landed won't have a kyber record on disk. Mint one lazily,
        // store it, and CRUCIALLY reset `preKeysUploaded = false` so
        // the next `ensurePreKeysUploaded()` actually sends the kyber
        // to the server. Without this reset, peers fetching the
        // bundle through the relay would get `kyberPreKey: null` →
        // PreKeyBundle.init throws → no message ever reaches them.
        // ────────────────────────────────────────────────────────────
        let backFilled = persisted.kyberPreKeyRecord == nil || persisted.kyberPreKeyId == 0
        if backFilled {
            let kyberPair = KEMKeyPair.generate()
            let kyberSignature = identity.privateKey.generateSignature(
                message: kyberPair.publicKey.serialize()
            )
            let kyberRecord = try KyberPreKeyRecord(
                id: kyberPreKeyInitialId,
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                keyPair: kyberPair,
                signature: kyberSignature
            )
            try store.storeKyberPreKey(kyberRecord, id: kyberPreKeyInitialId, context: NullContext())

            try persistence.write(Snapshot(
                identityKeyPair: persisted.identityKeyPair,
                identityPublicKey: persisted.identityPublicKey,
                registrationId: persisted.registrationId,
                signedPreKeyId: persisted.signedPreKeyId,
                signedPreKeyRecord: persisted.signedPreKeyRecord,
                oneTimePreKeyRecords: persisted.oneTimePreKeyRecords,
                kyberPreKeyRecord: kyberRecord.serialize(),
                kyberPreKeyId: kyberPreKeyInitialId,
                preKeysUploaded: false
            ))
            logger.info("Kyber back-fill — preKeysUploaded reset to false")
        }

        return store
    }

    // MARK: - Snapshot wire format

    /// Persisted snapshot — re-expressed in Swift from
    /// `SignalIdentityStore.Snapshot` on Android. Every byte array is
    /// a libsignal `.serialize()` output that the matching init-from-
    /// bytes ctor can rehydrate.
    struct Snapshot: Codable, Equatable, Sendable {
        /// `IdentityKeyPair.serialize()` bytes.
        let identityKeyPair: Data
        /// `identity.publicKey.serialize()` — duplicated so the chat
        /// layer can base64 it without round-tripping through libsignal
        /// when it just needs the public half.
        let identityPublicKey: Data
        let registrationId: UInt32
        let signedPreKeyId: UInt32
        /// `SignedPreKeyRecord.serialize()` bytes.
        let signedPreKeyRecord: Data
        /// Array of `PreKeyRecord.serialize()` byte blobs.
        let oneTimePreKeyRecords: [Data]
        /// `KyberPreKeyRecord.serialize()` bytes. Nullable on pre-
        /// commit snapshots — the back-fill path rehydrates it and
        /// resets `preKeysUploaded`.
        let kyberPreKeyRecord: Data?
        let kyberPreKeyId: UInt32
        /// Flag flipped true once the initial batch has been uploaded
        /// to `/v1/keys/prekeys`. Reset to false by the kyber back-fill
        /// path — see `rehydrate`.
        let preKeysUploaded: Bool
    }
}

// MARK: - Shared Signal Protocol store (existing helper extended)

/// Process-wide holder for the `InMemorySignalProtocolStore`.
/// Extended with a cache hit helper so `SignalIdentityKeys.loadOrGenerate`
/// can return the already-configured store without reconfiguring.
final class SignalStore: @unchecked Sendable {
    static let shared = SignalStore()

    private let queue = DispatchQueue(label: "io.okaiwa.signal.store")
    private var store: InMemorySignalProtocolStore?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SignalStore")

    private init() {}

    /// Return the already-configured store if any, otherwise nil.
    /// Used by `SignalIdentityKeys.loadOrGenerate` to short-circuit
    /// the rehydrate path when the process already built one.
    func cached() -> InMemorySignalProtocolStore? {
        queue.sync { store }
    }

    @discardableResult
    func configure(
        identity: IdentityKeyPair,
        registrationId: UInt32
    ) throws -> InMemorySignalProtocolStore {
        try queue.sync {
            let freshStore = InMemorySignalProtocolStore(
                identity: identity,
                registrationId: registrationId
            )
            self.store = freshStore
            logger.info("Signal protocol store configured (registrationId=\(registrationId, privacy: .public))")
            return freshStore
        }
    }

    func require() throws -> InMemorySignalProtocolStore {
        try queue.sync {
            guard let store else {
                throw AppError.keyError(reason: "Signal store is not initialised — register first.")
            }
            return store
        }
    }
}

// MARK: - Persistence (iOS twin of SignalIdentityStore.kt)

/// Keychain-backed persistence for the `SignalIdentityKeys.Snapshot`.
/// Mirrors `SignalIdentityStore.kt`; a single JSON blob is stored in
/// the Keychain under `io.okaiwa.signal.identity.v1` with the standard
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` via `KeychainManager`.
///
/// Lifecycle policy matches Android: the Signal keys live across
/// sign-outs. Clearing the session tokens is recoverable; clearing
/// the identity keys invalidates every existing conversation so the
/// store is explicitly isolated.
final class SignalIdentityPersistence: Sendable {
    static let shared = SignalIdentityPersistence()

    private let keychain: KeychainManager
    private let key: String = "io.okaiwa.signal.identity.v1"

    init(keychain: KeychainManager = KeychainManager()) {
        self.keychain = keychain
    }

    func read() throws -> SignalIdentityKeys.Snapshot? {
        guard let data = try keychain.load(forKey: key) else { return nil }
        return try JSONDecoder().decode(SignalIdentityKeys.Snapshot.self, from: data)
    }

    func write(_ snapshot: SignalIdentityKeys.Snapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try keychain.save(data: data, forKey: key)
    }

    func markPreKeysUploaded() throws {
        guard let existing = try read() else { return }
        let bumped = SignalIdentityKeys.Snapshot(
            identityKeyPair: existing.identityKeyPair,
            identityPublicKey: existing.identityPublicKey,
            registrationId: existing.registrationId,
            signedPreKeyId: existing.signedPreKeyId,
            signedPreKeyRecord: existing.signedPreKeyRecord,
            oneTimePreKeyRecords: existing.oneTimePreKeyRecords,
            kyberPreKeyRecord: existing.kyberPreKeyRecord,
            kyberPreKeyId: existing.kyberPreKeyId,
            preKeysUploaded: true
        )
        try write(bumped)
    }

    func clear() throws {
        try keychain.delete(forKey: key)
    }
}

// MARK: - Legacy API (kept for source compatibility)

extension SignalIdentityKeys {
    /// Kept so older call sites that did `SignalIdentityKeys.generate()`
    /// keep compiling. Delegates to `loadOrGenerate` + `registrationBundle`
    /// so fresh runs install the full (identity + signed + OPKs + kyber)
    /// snapshot into the Keychain on the very first call rather than
    /// only the signed-pre-key the pre-iteration implementation wrote.
    static func generate() throws -> Bundle {
        _ = try loadOrGenerate()
        return try registrationBundle()
    }
}
