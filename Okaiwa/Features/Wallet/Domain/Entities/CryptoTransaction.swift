// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// A blockchain transaction.
///
/// Represents both outgoing (signed locally) and incoming (observed on-chain)
/// transactions. Transaction data is stored locally in the encrypted database.
struct CryptoTransaction: Identifiable, Codable, Sendable, Equatable {

    /// Unique identifier. For confirmed transactions, this is the on-chain hash.
    /// For pending transactions, a local UUID is used until confirmation.
    let id: String

    /// On-chain transaction hash (hex string).
    let hash: String

    /// Sender address.
    let from: String

    /// Recipient address.
    let to: String

    /// Transaction amount in the token's smallest unit (wei for ETH).
    let amount: Decimal

    /// Human-readable amount (e.g., "1.5" ETH).
    let displayAmount: String

    /// Token symbol (e.g., "ETH", "USDC").
    let token: String

    /// Token contract address. `nil` for native token transfers.
    let tokenContractAddress: String?

    /// Blockchain network.
    let chain: Wallet.Chain

    /// Transaction status.
    var status: Status

    /// Block timestamp (nil if pending).
    var timestamp: Date?

    /// Block number (nil if pending).
    var blockNumber: UInt64?

    /// Gas fee paid in native token.
    let fee: Decimal

    /// Gas price in Gwei (for display).
    let gasPriceGwei: Decimal?

    /// Nonce used for this transaction.
    let nonce: UInt64

    /// Optional note/memo attached by the user.
    var note: String?

    /// Whether this transaction was initiated from within an Okaiwa chat.
    let isInChatPayment: Bool

    /// Associated conversation ID (for in-chat payments).
    let conversationId: String?

    // MARK: - Status

    enum Status: String, Codable, Sendable {
        /// Transaction is being constructed and signed.
        case preparing
        /// Transaction has been broadcast to the network.
        case pending
        /// Transaction is confirmed on-chain.
        case confirmed
        /// Transaction failed (reverted, out of gas, etc.).
        case failed
        /// Transaction was replaced (speed up / cancel).
        case replaced
    }

    // MARK: - Direction

    enum Direction: Sendable {
        case sent
        case received
    }
}

// MARK: - Convenience

extension CryptoTransaction {

    /// Determine transaction direction relative to a wallet address.
    func direction(for walletAddress: String) -> Direction {
        if from.lowercased() == walletAddress.lowercased() {
            return .sent
        }
        return .received
    }

    /// Shortened hash for display (e.g., "0xabcd...1234").
    var shortHash: String {
        guard hash.count > 14 else { return hash }
        return "\(hash.prefix(10))...\(hash.suffix(4))"
    }

    /// Block explorer URL for this transaction.
    var explorerURL: URL {
        chain.explorerURL.appendingPathComponent("tx/\(hash)")
    }

    /// Whether the transaction is still pending confirmation.
    var isPending: Bool {
        status == .pending || status == .preparing
    }

    /// Whether the transaction is a native token transfer (not ERC-20).
    var isNativeTransfer: Bool {
        tokenContractAddress == nil
    }

    /// Formatted fee string (e.g., "0.002 ETH").
    var feeDisplay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 2
        let formatted = formatter.string(from: fee as NSDecimalNumber) ?? "\(fee)"
        return "\(formatted) \(chain.nativeToken)"
    }
}
