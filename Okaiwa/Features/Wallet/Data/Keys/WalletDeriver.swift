import Foundation
import WalletCore

/// Derives chain-specific addresses from a BIP-39 mnemonic using
/// wallet-core's HDWallet + CoinType. The derivation path per chain
/// is the one wallet-core picks by default (`CoinType.derivationPath`)
/// which in turn matches each chain's SLIP-44 / BIP-44 convention:
///
///   - Ethereum: `m/44'/60'/0'/0/0`
///   - Bitcoin (bech32, SegWit): `m/84'/0'/0'/0/0`
///   - Solana (ed25519): `m/44'/501'/0'`
///
/// Keeping derivation on the iOS side — rather than roundtripping
/// through the backend — means the mnemonic never leaves the device,
/// which is what keeps Okaiwa "non-custodial by construction".
public enum WalletDeriver {
    public enum Error: Swift.Error {
        case invalidMnemonic
    }

    /// The three top-level chains we surface in the wallet UI. Mirrors
    /// the enum in `WalletDeriver.kt`.
    public enum Chain: String, Sendable {
        case ethereum
        case bitcoin
        case solana

        fileprivate var coinType: CoinType {
            switch self {
            case .ethereum: return .ethereum
            case .bitcoin:  return .bitcoin
            case .solana:   return .solana
            }
        }
    }

    /// Shape of the derived artefacts. `address` is the user-facing
    /// string (EIP-55 checksummed for ETH, bech32 for BTC, base58 for
    /// SOL), `publicKey` is the raw compressed public key hex so the
    /// server can associate the account without needing the private
    /// half.
    public struct DerivedAccount: Equatable, Sendable {
        public let chain: Chain
        public let address: String
        public let publicKeyHex: String
    }

    /// Derive all three chains at once. We join on whitespace because
    /// wallet-core's `HDWallet(mnemonic:passphrase:)` expects a space-
    /// separated mnemonic string regardless of how the caller stored
    /// the words.
    public static func derive(
        mnemonic: [String],
        passphrase: String = ""
    ) throws -> [DerivedAccount] {
        let joined = mnemonic.joined(separator: " ")
        guard let wallet = HDWallet(mnemonic: joined, passphrase: passphrase) else {
            throw Error.invalidMnemonic
        }

        return Chain.allCases.map { chain in
            let coin = chain.coinType
            let address = wallet.getAddressForCoin(coin: coin)
            let publicKey = wallet.getKeyForCoin(coin: coin).getPublicKey(coinType: coin)
            return DerivedAccount(
                chain: chain,
                address: address,
                publicKeyHex: publicKey.data.hexString
            )
        }
    }

    /// Convenience: single-chain derivation when the caller only needs
    /// one address (e.g., "give me the ETH address to display on the
    /// wallet screen").
    public static func derive(
        chain: Chain,
        mnemonic: [String],
        passphrase: String = ""
    ) throws -> DerivedAccount {
        let joined = mnemonic.joined(separator: " ")
        guard let wallet = HDWallet(mnemonic: joined, passphrase: passphrase) else {
            throw Error.invalidMnemonic
        }
        let coin = chain.coinType
        let address = wallet.getAddressForCoin(coin: coin)
        let publicKey = wallet.getKeyForCoin(coin: coin).getPublicKey(coinType: coin)
        return DerivedAccount(
            chain: chain,
            address: address,
            publicKeyHex: publicKey.data.hexString
        )
    }
}

extension WalletDeriver.Chain: CaseIterable {}

// MARK: - Data -> hex helper

private extension Data {
    /// Lowercase, unpadded hex. Kept private because the codebase
    /// already has its own conventions for hex handling elsewhere and
    /// we don't want a second public helper competing with them.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
