// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// Use case for sending a crypto transaction.
///
/// Orchestrates the full send flow:
/// 1. Validate recipient address (or resolve ENS)
/// 2. Check sufficient balance (amount + estimated gas)
/// 3. Sign the transaction using Secure Enclave
/// 4. Broadcast to the blockchain network
/// 5. Watch for confirmation
///
/// Private keys never leave the Secure Enclave — signing happens on-chip.
final class SendCryptoUseCase: Sendable {

    private let walletRepository: WalletRepository
    private let secureEnclaveManager: SecureEnclaveManager
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SendCrypto")

    init(
        walletRepository: WalletRepository,
        secureEnclaveManager: SecureEnclaveManager = SecureEnclaveManager()
    ) {
        self.walletRepository = walletRepository
        self.secureEnclaveManager = secureEnclaveManager
    }

    // MARK: - Execute

    /// Send a crypto transaction.
    ///
    /// - Parameters:
    ///   - amount: Amount to send in human-readable format (e.g., "1.5").
    ///   - recipientAddress: Destination address or ENS name.
    ///   - chain: Blockchain network.
    ///   - tokenContract: ERC-20 contract address (nil for native token).
    ///   - note: Optional user note.
    ///   - conversationId: Associated conversation for in-chat payments.
    /// - Returns: The transaction with pending status.
    func execute(
        amount: Decimal,
        recipientAddress: String,
        chain: Wallet.Chain,
        tokenContract: String? = nil,
        note: String? = nil,
        conversationId: String? = nil
    ) async throws -> CryptoTransaction {
        logger.info("Initiating transaction on \(chain.rawValue)")

        // Step 1: Resolve ENS if needed
        let resolvedAddress = try await resolveAddress(recipientAddress, chain: chain)

        // Step 2: Validate address
        guard walletRepository.isValidAddress(resolvedAddress, chain: chain) else {
            throw AppError.invalidAddress(address: recipientAddress)
        }

        // Step 3: Get sender wallet
        guard let wallet = try await walletRepository.getWallet(chain: chain) else {
            throw AppError.transactionSigningFailed(reason: "No wallet found for \(chain.displayName)")
        }

        // Step 4: Estimate gas
        let estimatedFee = try await walletRepository.estimateGas(
            from: wallet.address,
            to: resolvedAddress,
            amount: amount,
            chain: chain,
            tokenContract: tokenContract
        )

        // Step 5: Check balance
        try validateBalance(
            wallet: wallet,
            amount: amount,
            fee: estimatedFee,
            tokenContract: tokenContract
        )

        // Step 6: Sign and broadcast
        logger.info("Signing transaction via Secure Enclave")

        let transaction = try await walletRepository.sendTransaction(
            from: wallet,
            to: resolvedAddress,
            amount: amount,
            chain: chain,
            tokenContract: tokenContract,
            note: note,
            conversationId: conversationId
        )

        logger.info("Transaction broadcast: \(transaction.shortHash) — status: \(transaction.status.rawValue)")

        return transaction
    }

    /// Estimate the total cost of a transaction (amount + gas).
    ///
    /// - Parameters:
    ///   - amount: Amount to send.
    ///   - recipientAddress: Destination address.
    ///   - chain: Blockchain network.
    ///   - tokenContract: ERC-20 contract (nil for native).
    /// - Returns: Tuple of (estimated fee, total cost in native token).
    func estimateCost(
        amount: Decimal,
        recipientAddress: String,
        chain: Wallet.Chain,
        tokenContract: String? = nil
    ) async throws -> (fee: Decimal, totalNativeCost: Decimal) {
        guard let wallet = try await walletRepository.getWallet(chain: chain) else {
            throw AppError.transactionSigningFailed(reason: "No wallet for \(chain.displayName)")
        }

        let fee = try await walletRepository.estimateGas(
            from: wallet.address,
            to: recipientAddress,
            amount: amount,
            chain: chain,
            tokenContract: tokenContract
        )

        // For native transfers, total = amount + fee
        // For token transfers, total native cost = fee only (amount is in tokens)
        let totalNative = tokenContract == nil ? amount + fee : fee
        return (fee, totalNative)
    }

    // MARK: - Private

    /// Resolve an ENS name or return the address as-is.
    private func resolveAddress(_ input: String, chain: Wallet.Chain) async throws -> String {
        // Check if it looks like an ENS name (contains a dot, doesn't start with 0x)
        if input.contains(".") && !input.hasPrefix("0x") {
            guard let resolved = try await walletRepository.resolveENS(name: input) else {
                throw AppError.invalidAddress(address: "\(input) (ENS name not found)")
            }
            logger.info("Resolved ENS \(input) to \(resolved.prefix(10))...")
            return resolved
        }
        return input
    }

    /// Validate that the wallet has sufficient balance for the transaction.
    private func validateBalance(
        wallet: Wallet,
        amount: Decimal,
        fee: Decimal,
        tokenContract: String?
    ) throws {
        if let tokenContract {
            // ERC-20 transfer: check token balance + native balance for gas
            guard let tokenBalance = wallet.tokenBalances.first(
                where: { $0.contractAddress.lowercased() == tokenContract.lowercased() }
            ) else {
                throw AppError.insufficientBalance(required: "\(amount)", available: "0")
            }

            if tokenBalance.balance < amount {
                throw AppError.insufficientBalance(
                    required: "\(amount) \(tokenBalance.symbol)",
                    available: "\(tokenBalance.balance) \(tokenBalance.symbol)"
                )
            }

            if wallet.balance < fee {
                throw AppError.insufficientBalance(
                    required: "\(fee) \(wallet.chain.nativeToken) (gas)",
                    available: "\(wallet.balance) \(wallet.chain.nativeToken)"
                )
            }
        } else {
            // Native transfer: check total (amount + gas)
            let total = amount + fee
            if wallet.balance < total {
                throw AppError.insufficientBalance(
                    required: "\(total) \(wallet.chain.nativeToken)",
                    available: "\(wallet.balance) \(wallet.chain.nativeToken)"
                )
            }
        }
    }
}
