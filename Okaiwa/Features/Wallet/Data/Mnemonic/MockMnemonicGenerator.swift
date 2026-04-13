import Foundation

/// Mock 24-word BIP-39 mnemonic generator — mirrors
/// `MockMnemonicGenerator.kt`.
///
/// Deliberately NOT cryptographically strong. The wallet-core Rust
/// crate replaces this through the FFI binding once the iOS XCFramework
/// is published. See the Android twin file for the 24 vs 12 word
/// rationale (256 bits of entropy for the quantum-era safety margin).
public enum MockMnemonicGenerator {
    private static let wordlist: [String] = [
        "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
        "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
        "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
        "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",
        "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
        "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",
        "alcohol", "alert", "alien", "alley", "allow", "almost", "alone", "alpha",
        "already", "also", "alter", "always", "amateur", "amazing", "among", "amount",
        "amused", "analyst", "anchor", "ancient", "anger", "angle", "angry", "animal",
        "ankle", "announce", "annual", "another", "answer", "antenna", "antique", "anxiety",
        "apart", "apology", "appear", "apple", "approve", "april", "arch", "arctic",
        "area", "arena", "argue", "arm", "armed", "armor", "army", "around",
        "arrange", "arrest", "arrive", "arrow", "art", "artefact", "artist", "artwork",
        "ask", "aspect", "assault", "asset", "assist", "assume", "asthma", "athlete",
        "atom", "attack", "attend", "attitude", "attract", "auction", "audit", "august",
        "aunt", "author", "auto", "autumn", "average", "avocado", "avoid", "awake",
    ]

    public static func generate24() -> [String] {
        var pool = wordlist
        var result: [String] = []
        for _ in 0..<24 {
            let i = Int.random(in: 0..<pool.count)
            result.append(pool.remove(at: i))
        }
        return result
    }
}
