import Foundation
import LibSignalClient
import os

/// Real Signal Protocol identity material — iOS counterpart of the
/// forthcoming Kotlin implementation backed by libsignal's Android
/// bindings. Replaces the interim `MockSignalKeyBundle` that only
/// emitted random bytes shaped like a Signal payload.
///
/// What this generates:
///   - An `IdentityKeyPair` (Curve25519) via `IdentityKeyPair.generate()`.
///   - A `SignedPreKeyRecord` with an explicit id + timestamp + a
///     signature computed from the long-term identity private key over
///     the signed pre-key public bytes. The backend re-verifies that
///     signature against the identity public key, so a mismatched
///     signature would have the server reject the registration.
///   - A 14-bit positive `registrationId`, matching the bit width the
///     Vine validator on okaiwa-server enforces.
///
/// The resulting material is persisted into a shared
/// `InMemorySignalProtocolStore` so the rest of the app — especially
/// the chat encryption helpers in `SignalSession` — sees the same
/// identity the server was registered with. The store itself is an
/// in-memory cache for this milestone; a Keychain-backed store is the
/// natural next step and is expected to slot in behind the same
/// `SignalIdentityKeys.shared` entry point without touching call sites.
///
/// The exported `Bundle` struct mirrors the wire format expected by
/// `RegisterRequest` — every field is base64 with no line breaks, to
/// stay byte-for-byte identical to what Android sends.
enum SignalIdentityKeys {

    // MARK: - Wire format (matches okaiwa-server validators)

    /// Base64-encoded signed pre-key, one-to-one with the Android
    /// `SignedPreKeyDto` and the backend Vine schema.
    struct SignedPreKey: Codable, Equatable, Sendable {
        let keyId: Int
        let publicKey: String
        let signature: String
    }

    /// Payload shipped to `/v1/auth/register`. Callers should treat it
    /// as opaque and forward it to `IdentityAuthClient`.
    struct Bundle: Equatable, Sendable {
        let identityPublicKey: String
        let signedPreKey: SignedPreKey
        let registrationId: Int
    }

    // MARK: - Generation

    /// Deterministic id used for the freshly-generated signed pre-key.
    /// The server stores it as an integer; higher byte values are fine
    /// because the Vine validator accepts any positive `Int32`. We keep
    /// the current epoch so key rotation records stay ordered.
    private static func freshSignedPreKeyId() -> UInt32 {
        // UInt32 fits 32 bits; we mask to 31 bits so the `Int` cast on
        // the wire never goes negative on platforms where `Int` is 32
        // bits (it isn't on arm64, but the defensive mask costs nothing
        // and keeps the DTO identical to Android's `Int.MAX_VALUE`
        // clamp).
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        return UInt32(truncatingIfNeeded: now) & 0x7fff_ffff
    }

    /// Uniform 14-bit registration id in [1, 2^14) — matches Android.
    private static func freshRegistrationId() -> UInt32 {
        // `UInt32.random(in:)` is uniform and backed by `SystemRandom`,
        // which on Apple platforms is `arc4random_buf`. Good enough for
        // an identifier the server treats as opaque.
        return UInt32.random(in: 1..<0x4000)
    }

    /// Generate and persist a fresh identity + signed pre-key pair.
    ///
    /// Must run on a cooperative thread — `IdentityKeyPair.generate()`
    /// is CPU-bound but quick (single Curve25519 keygen + one Ed25519
    /// signature). We keep the throwing signature in case a future
    /// switch to a Keychain-backed store surfaces I/O errors.
    static func generate() throws -> Bundle {
        let identity = IdentityKeyPair.generate()
        let registrationId = freshRegistrationId()

        // Signed pre-key material. libsignal's SignedPreKeyRecord
        // constructor accepts the *private* key and derives the public
        // half internally; we compute the signature ourselves because
        // the wire format needs both the public bytes and the raw 64-
        // byte Ed25519 signature.
        let signedPrivate = PrivateKey.generate()
        let signedPublic = signedPrivate.publicKey
        let signedPreKeyId = freshSignedPreKeyId()
        let timestampMs = UInt64(Date().timeIntervalSince1970 * 1000)

        let signature = identity.privateKey.generateSignature(
            message: signedPublic.serialize()
        )

        let signedPreKeyRecord = try SignedPreKeyRecord(
            id: signedPreKeyId,
            timestamp: timestampMs,
            privateKey: signedPrivate,
            signature: signature
        )

        // Persist everything into the shared in-memory store so peer
        // encrypt/decrypt can find the same identity later.
        let store = try SignalStore.shared.configure(
            identity: identity,
            registrationId: registrationId
        )
        try store.storeSignedPreKey(
            signedPreKeyRecord,
            id: signedPreKeyId,
            context: NullContext()
        )

        return Bundle(
            identityPublicKey: identity.publicKey.serialize().base64EncodedString(),
            signedPreKey: SignedPreKey(
                keyId: Int(signedPreKeyId),
                publicKey: signedPublic.serialize().base64EncodedString(),
                signature: signature.base64EncodedString()
            ),
            registrationId: Int(registrationId)
        )
    }
}

// MARK: - Shared Signal Protocol store

/// Process-wide holder for the `InMemorySignalProtocolStore` that every
/// Signal operation (pre-key generation, session build, encrypt,
/// decrypt) reads from.
///
/// Why a separate holder instead of living on `SignalIdentityKeys`:
/// `InMemorySignalProtocolStore` is not thread-safe, but the only
/// cross-thread access we need is "resolve the singleton", and
/// serialising on a `DispatchQueue` keeps the lifetime explicit without
/// forcing every caller through an actor hop. When the Keychain-backed
/// store lands it will replace this type wholesale.
final class SignalStore: @unchecked Sendable {
    static let shared = SignalStore()

    private let queue = DispatchQueue(label: "io.okaiwa.signal.store")
    private var store: InMemorySignalProtocolStore?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SignalStore")

    private init() {}

    /// Install a fresh store for the given identity + registration id.
    /// If called twice (e.g., re-register) the previous store is
    /// discarded — all session state goes with it, which matches the
    /// expectation that a new registration invalidates old sessions.
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

    /// Throws `AppError.keyError` if the store has not been configured
    /// yet — callers of encrypt/decrypt should always run registration
    /// first.
    func require() throws -> InMemorySignalProtocolStore {
        try queue.sync {
            guard let store else {
                throw AppError.keyError(reason: "Signal store is not initialised — register first.")
            }
            return store
        }
    }
}
