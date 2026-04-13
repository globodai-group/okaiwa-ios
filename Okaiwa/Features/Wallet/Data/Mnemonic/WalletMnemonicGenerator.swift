import Foundation
import WalletCore

/// Real BIP-39 mnemonic generator, backed by Trust Wallet's wallet-
/// core. Replaces the throwaway `MockMnemonicGenerator` that only
/// sampled from a hardcoded English wordlist.
///
/// We deliberately request a 256-bit entropy wallet (24 words) instead
/// of the more common 128-bit (12 words): the extra 128 bits bring the
/// post-quantum Grover bound up to 128 effective bits of security,
/// which matches the thresholds that Okaiwa applies everywhere else
/// (ChaCha20-Poly1305 keys, long-term identity keys, Signal Kyber pre-
/// keys). See the mirrored rationale comment in `WalletMnemonic.kt`.
///
/// The returned array is always exactly 24 non-empty lowercase
/// words. If wallet-core ever fails to allocate the underlying
/// `HDWallet` object we fall back to throwing rather than returning
/// a shorter list — an incomplete mnemonic would corrupt address
/// derivation downstream and silently lose user funds.
public enum WalletMnemonicGenerator {
    public enum Error: Swift.Error {
        case walletCreationFailed
        case unexpectedWordCount(Int)
    }

    /// 256-bit entropy → 24 BIP-39 words. Empty passphrase (BIP-39
    /// "salt") because Okaiwa does not expose the optional 25th-word
    /// concept to users; we protect the seed with device-level
    /// security instead (Secure Enclave / Face ID).
    public static func generate24() throws -> [String] {
        guard let wallet = HDWallet(strength: 256, passphrase: "") else {
            throw Error.walletCreationFailed
        }
        let words = wallet.mnemonic.split(separator: " ").map(String.init)
        guard words.count == 24 else {
            throw Error.unexpectedWordCount(words.count)
        }
        return words
    }
}
