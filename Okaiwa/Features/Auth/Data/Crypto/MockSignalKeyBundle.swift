import Foundation
import Security

/// Placeholder Signal Protocol key bundle — iOS mirror of
/// `MockSignalKeyBundle.kt`.
///
/// Generates cryptographically random bytes (via `SecRandomCopyBytes`)
/// that satisfy the server-side Vine validators: a 32-byte identity key,
/// a 32-byte signed pre-key public component, a 64-byte signature, and
/// a 14-bit positive `registrationId`. Everything is base64-encoded with
/// no line breaks so the payload matches exactly what Android sends.
///
/// Not usable for real Signal session setup — the backend stores the
/// values but no peer will be able to derive a shared secret from them.
/// This is fine for the auth-plumbing milestone because no encrypted
/// messaging is wired yet. Swap for the real libsignal generator the
/// moment `okaiwa-signal-core` ships its XCFramework.
enum MockSignalKeyBundle {
    struct SignedPreKey: Codable {
        let keyId: Int
        let publicKey: String
        let signature: String
    }

    struct Bundle {
        let identityPublicKey: String
        let signedPreKey: SignedPreKey
        let registrationId: Int
    }

    static func generate() -> Bundle {
        let identityKey = randomBytes(count: 32)
        let signedPreKeyPub = randomBytes(count: 32)
        let signature = randomBytes(count: 64)

        // 14-bit positive int, guaranteed non-zero so the server
        // `vine.number().positive()` check passes.
        let registrationId = 1 + randomInt(upperBound: 0x3fff)

        return Bundle(
            identityPublicKey: identityKey.base64EncodedString(options: []),
            signedPreKey: SignedPreKey(
                keyId: 1 + randomInt(upperBound: Int32.max - 1),
                publicKey: signedPreKeyPub.base64EncodedString(options: []),
                signature: signature.base64EncodedString(options: [])
            ),
            registrationId: registrationId
        )
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")
        return bytes
    }

    /// Uniform integer in [0, upperBound). Rejection-sampled so there is
    /// no modulo bias when `upperBound` is not a power of two.
    private static func randomInt<T: FixedWidthInteger>(upperBound: T) -> Int {
        let bound = UInt64(upperBound)
        precondition(bound > 0, "upperBound must be positive")
        let bucket = UInt64.max - (UInt64.max % bound)

        while true {
            var raw: UInt64 = 0
            let status = withUnsafeMutableBytes(of: &raw) { buffer -> Int32 in
                guard let base = buffer.baseAddress else { return errSecAllocate }
                return SecRandomCopyBytes(kSecRandomDefault, buffer.count, base)
            }
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")

            if raw < bucket {
                return Int(raw % bound)
            }
        }
    }
}
