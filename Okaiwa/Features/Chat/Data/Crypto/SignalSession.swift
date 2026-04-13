import Foundation
import LibSignalClient
import os

/// Thin wrapper around libsignal's top-level `signalEncrypt` /
/// `signalDecrypt` entry points. Centralises the store context so the
/// chat layer never has to know about libsignal's protocol types.
///
/// The session layer assumes the caller has already run the Signal
/// Protocol X3DH handshake — i.e. a `SessionRecord` for
/// `ProtocolAddress` exists in the shared `InMemorySignalProtocolStore`.
/// The initial handshake (processPreKeyBundle) is not wired yet and is
/// tracked as follow-up work once contact discovery lands.
///
/// Every public method is `async throws`: libsignal's Swift API is
/// synchronous and CPU-bound, but wrapping it in an `async` signature
/// keeps the call sites future-proof for when we move encryption to a
/// background actor.
enum SignalSession {
    private static let logger = Logger(
        subsystem: "io.okaiwa.app",
        category: "SignalSession"
    )

    // MARK: - Encryption

    /// Encrypt `plaintext` for `address`. Returns the serialized
    /// ciphertext bytes — the caller is responsible for transporting
    /// them verbatim to the recipient. The first message in a session
    /// returns a `PreKeySignalMessage`, every subsequent message a
    /// `SignalMessage`; both share the `CiphertextMessage` façade.
    ///
    /// Stub: wiring into the chat UI will happen in the follow-up
    /// milestone where the outgoing-message pipeline is built.
    static func encryptForRecipient(
        _ address: ProtocolAddress,
        plaintext: Data
    ) async throws -> Data {
        let store = try SignalStore.shared.require()
        let localAddress = try localAddressFor(store: store)

        do {
            let ciphertext = try signalEncrypt(
                message: plaintext,
                for: address,
                localAddress: localAddress,
                sessionStore: store,
                identityStore: store,
                context: NullContext()
            )
            return ciphertext.serialize()
        } catch {
            logger.error("encrypt failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.encryptionFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Decryption

    /// Decrypt a `SignalMessage` from a sender. The ciphertext bytes
    /// are expected to round-trip through `SignalMessage(bytes:)` — if
    /// the payload is actually a `PreKeySignalMessage` (i.e. the very
    /// first message of the session) the caller must dispatch to a
    /// `signalDecryptPreKey`-based path instead; that variant requires
    /// the pre-key + kyber pre-key stores that the initial handshake
    /// landing will populate.
    ///
    /// Stub: wired for a plain `SignalMessage` today so session-
    /// resumption decryption compiles end-to-end.
    static func decryptFromSender(
        _ address: ProtocolAddress,
        ciphertext: Data
    ) async throws -> Data {
        let store = try SignalStore.shared.require()

        do {
            let message = try SignalMessage(bytes: ciphertext)
            return try signalDecrypt(
                message: message,
                from: address,
                sessionStore: store,
                identityStore: store,
                context: NullContext()
            )
        } catch {
            logger.error("decrypt failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.encryptionFailed(reason: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// libsignal's encrypt() requires a `localAddress` so the session
    /// layer can stamp outgoing sealed-sender envelopes with our own
    /// identity. We synthesize one from the account's registrationId;
    /// once the accountId-as-ServiceId path is wired, swap this out
    /// for the real ServiceId-aware initializer.
    private static func localAddressFor(
        store: InMemorySignalProtocolStore
    ) throws -> ProtocolAddress {
        let registrationId = try store.localRegistrationId(context: NullContext())
        return try ProtocolAddress(
            name: "self.\(registrationId)",
            deviceId: 1
        )
    }
}
