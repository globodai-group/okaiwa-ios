// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// A crypto wallet derived from the user's HD seed.
///
/// Each wallet represents one address on one chain. Multiple wallets
/// can be derived from the same seed using different derivation paths.
/// Private keys are held in the Secure Enclave and never exported.
struct Wallet: Identifiable, Codable, Sendable, Equatable {

    /// Unique wallet identifier (derived from chain + address).
    var id: String { "\(chain.rawValue):\(address)" }

    /// On-chain address (e.g., "0x1234...abcd").
    let address: String

    /// Blockchain network.
    let chain: Chain

    /// Current balance in the native token.
    var balance: Decimal

    /// BIP-44 derivation path (e.g., "m/44'/60'/0'/0/0").
    let derivationPath: String

    /// Whether this is the default wallet for its chain.
    var isDefault: Bool

    /// Token balances (ERC-20, etc.).
    var tokenBalances: [TokenBalance]

    /// Last time the balance was refreshed from the RPC node.
    var lastSyncedAt: Date?

    // MARK: - Nested Types

    /// Supported blockchain networks.
    enum Chain: String, Codable, Sendable, CaseIterable {
        case ethereum = "ethereum"
        case polygon = "polygon"
        case arbitrum = "arbitrum"
        case base = "base"

        /// Human-readable display name.
        var displayName: String {
            switch self {
            case .ethereum: return "Ethereum"
            case .polygon: return "Polygon"
            case .arbitrum: return "Arbitrum"
            case .base: return "Base"
            }
        }

        /// Chain ID for EIP-155 signing.
        var chainId: Int {
            switch self {
            case .ethereum: return 1
            case .polygon: return 137
            case .arbitrum: return 42161
            case .base: return 8453
            }
        }

        /// Native token symbol.
        var nativeToken: String {
            switch self {
            case .ethereum: return "ETH"
            case .polygon: return "MATIC"
            case .arbitrum: return "ETH"
            case .base: return "ETH"
            }
        }

        /// Default RPC endpoint.
        var rpcURL: URL {
            switch self {
            case .ethereum: return URL(string: "https://rpc.okaiwa.io/eth")!
            case .polygon: return URL(string: "https://rpc.okaiwa.io/polygon")!
            case .arbitrum: return URL(string: "https://rpc.okaiwa.io/arbitrum")!
            case .base: return URL(string: "https://rpc.okaiwa.io/base")!
            }
        }

        /// Block explorer base URL.
        var explorerURL: URL {
            switch self {
            case .ethereum: return URL(string: "https://etherscan.io")!
            case .polygon: return URL(string: "https://polygonscan.com")!
            case .arbitrum: return URL(string: "https://arbiscan.io")!
            case .base: return URL(string: "https://basescan.org")!
            }
        }

        /// SF Symbol name for the chain icon.
        var iconName: String {
            switch self {
            case .ethereum: return "diamond.fill"
            case .polygon: return "hexagon.fill"
            case .arbitrum: return "arrow.triangle.branch"
            case .base: return "circle.circle.fill"
            }
        }
    }

    /// ERC-20 token balance.
    struct TokenBalance: Codable, Sendable, Equatable, Identifiable {
        var id: String { contractAddress }
        let contractAddress: String
        let symbol: String
        let name: String
        let decimals: Int
        var balance: Decimal
        /// USD value of the balance (fetched from price oracle).
        var usdValue: Decimal?
    }
}

// MARK: - Convenience

extension Wallet {

    /// Shortened address for display (e.g., "0x1234...abcd").
    var shortAddress: String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    /// Total value in USD (native + tokens).
    var totalUSDValue: Decimal {
        let tokenTotal = tokenBalances.compactMap(\.usdValue).reduce(0, +)
        // Native token USD value would come from price oracle
        return tokenTotal
    }

    /// Whether the wallet has a non-zero balance.
    var hasBalance: Bool {
        balance > 0 || tokenBalances.contains { $0.balance > 0 }
    }

    /// Block explorer URL for this address.
    var explorerAddressURL: URL {
        chain.explorerURL.appendingPathComponent("address/\(address)")
    }
}
