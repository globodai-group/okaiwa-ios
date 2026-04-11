// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Repository protocol for wallet operations.
///
/// Abstracts blockchain interactions and local wallet storage.
/// Implementations coordinate between:
/// - Secure Enclave for key management and signing
/// - RPC nodes for balance queries and transaction broadcasting
/// - Local encrypted database for transaction history
///
/// All methods are async and throw `AppError` on failure.
protocol WalletRepository: Sendable {

    // MARK: - Wallet Management

    /// Get all wallets for the current user.
    func getWallets() async throws -> [Wallet]

    /// Get a specific wallet by chain.
    func getWallet(chain: Wallet.Chain) async throws -> Wallet?

    /// Create a new wallet for the specified chain.
    ///
    /// Derives the key pair from the HD seed stored in Secure Enclave
    /// using the standard BIP-44 derivation path.
    ///
    /// - Parameter chain: The blockchain network.
    /// - Returns: The newly created wallet.
    func createWallet(chain: Wallet.Chain) async throws -> Wallet

    /// Refresh the balance for a wallet from the RPC node.
    ///
    /// Updates both native token and ERC-20 token balances.
    ///
    /// - Parameter wallet: The wallet to refresh.
    /// - Returns: The wallet with updated balances.
    @discardableResult
    func refreshBalance(for wallet: Wallet) async throws -> Wallet

    /// Refresh balances for all wallets.
    func refreshAllBalances() async throws -> [Wallet]

    // MARK: - Transactions

    /// Get transaction history for a wallet.
    ///
    /// - Parameters:
    ///   - wallet: The wallet to query.
    ///   - limit: Maximum number of transactions.
    ///   - offset: Pagination offset.
    /// - Returns: Array of transactions, newest first.
    func getTransactions(
        for wallet: Wallet,
        limit: Int,
        offset: Int
    ) async throws -> [CryptoTransaction]

    /// Get a single transaction by hash.
    func getTransaction(hash: String, chain: Wallet.Chain) async throws -> CryptoTransaction?

    /// Estimate the gas fee for a transaction.
    ///
    /// - Parameters:
    ///   - from: Sender address.
    ///   - to: Recipient address.
    ///   - amount: Amount to send (in token's smallest unit).
    ///   - chain: Blockchain network.
    ///   - tokenContract: ERC-20 contract address (nil for native transfers).
    /// - Returns: Estimated fee in native token.
    func estimateGas(
        from: String,
        to: String,
        amount: Decimal,
        chain: Wallet.Chain,
        tokenContract: String?
    ) async throws -> Decimal

    /// Send a transaction.
    ///
    /// The transaction is signed using the Secure Enclave and broadcast
    /// to the blockchain network.
    ///
    /// - Parameters:
    ///   - from: Sender wallet.
    ///   - to: Recipient address.
    ///   - amount: Amount to send.
    ///   - chain: Blockchain network.
    ///   - tokenContract: ERC-20 contract (nil for native).
    ///   - note: Optional user note.
    ///   - conversationId: Associated chat conversation (for in-chat payments).
    /// - Returns: The pending transaction.
    func sendTransaction(
        from: Wallet,
        to: String,
        amount: Decimal,
        chain: Wallet.Chain,
        tokenContract: String?,
        note: String?,
        conversationId: String?
    ) async throws -> CryptoTransaction

    /// Watch for confirmation of a pending transaction.
    ///
    /// Returns an `AsyncStream` that emits status updates until the
    /// transaction is confirmed or fails.
    func watchTransaction(hash: String, chain: Wallet.Chain) -> AsyncStream<CryptoTransaction.Status>

    // MARK: - Address Validation

    /// Validate a blockchain address.
    ///
    /// - Parameters:
    ///   - address: The address to validate.
    ///   - chain: The blockchain network.
    /// - Returns: `true` if the address is valid for the chain.
    func isValidAddress(_ address: String, chain: Wallet.Chain) -> Bool

    /// Resolve an ENS name to an address.
    ///
    /// - Parameter name: ENS name (e.g., "vitalik.eth").
    /// - Returns: Resolved address, or `nil` if not found.
    func resolveENS(name: String) async throws -> String?
}
