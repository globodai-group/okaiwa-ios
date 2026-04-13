import CryptoKit
import Foundation

/// SHA-256 of an E.164 phone number, hex-encoded (64 lowercase chars).
///
/// Mirrors `PhoneHasher.kt` on Android — both platforms MUST produce the
/// same digest for the same input so that contact discovery (server-side
/// hash-match) behaves identically regardless of which OS a peer is on.
///
/// The input is normalized to strip spaces, hyphens and parentheses
/// before hashing, so `+33 6 12 34 56 78` and `+33612345678` collide.
/// No salt: discovery requires every client to produce the same hash
/// from the same number.
enum PhoneHasher {
    static func hashE164(_ rawE164: String) -> String {
        let normalized = normalize(rawE164)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalize(_ raw: String) -> String {
        var output = String()
        output.reserveCapacity(raw.count)
        for c in raw where c.isNumber || c == "+" {
            output.append(c)
        }
        return output
    }
}
