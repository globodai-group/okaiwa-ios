// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// View model for the wallet screen.
///
/// Manages loading wallet balances, transaction history,
/// and send/receive flows.
@Observable
final class WalletViewModel {

    // MARK: - State

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    enum SendState: Equatable {
        case idle
        case estimating
        case readyToSend(fee: String)
        case signing
        case broadcasting
        case success(txHash: String)
        case error(String)
    }

    // MARK: - Properties

    private(set) var wallets: [Wallet] = []
    private(set) var selectedWallet: Wallet?
    private(set) var transactions: [CryptoTransaction] = []
    private(set) var loadState: LoadState = .idle
    private(set) var sendState: SendState = .idle

    var selectedChain: Wallet.Chain = .ethereum {
        didSet {
            selectedWallet = wallets.first { $0.chain == selectedChain }
            Task { await loadTransactions() }
        }
    }

    // Send form
    var sendRecipient: String = ""
    var sendAmount: String = ""
    var sendNote: String = ""

    private var walletRepository: WalletRepository?
    private var sendCryptoUseCase: SendCryptoUseCase?
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "WalletVM")

    // MARK: - Configuration

    func configure(
        walletRepository: WalletRepository,
        sendCryptoUseCase: SendCryptoUseCase
    ) {
        self.walletRepository = walletRepository
        self.sendCryptoUseCase = sendCryptoUseCase
    }

    // MARK: - Loading

    /// Load all wallets and their balances.
    func loadWallets() async {
        loadState = .loading
        logger.info("Loading wallets")

        do {
            guard let repo = walletRepository else {
                loadState = .loaded
                return
            }

            wallets = try await repo.getWallets()

            // If no wallets exist, create defaults
            if wallets.isEmpty {
                for chain in Wallet.Chain.allCases {
                    let wallet = try await repo.createWallet(chain: chain)
                    wallets.append(wallet)
                }
            }

            // Refresh balances
            wallets = try await repo.refreshAllBalances()
            selectedWallet = wallets.first { $0.chain == selectedChain }

            await loadTransactions()
            loadState = .loaded
            logger.info("Loaded \(self.wallets.count) wallets")
        } catch {
            loadState = .error(AppError.from(error).localizedDescription)
            logger.error("Failed to load wallets: \(error.localizedDescription)")
        }
    }

    /// Load transaction history for the selected wallet.
    func loadTransactions() async {
        guard let wallet = selectedWallet, let repo = walletRepository else {
            transactions = []
            return
        }

        do {
            transactions = try await repo.getTransactions(for: wallet, limit: 50, offset: 0)
            logger.info("Loaded \(self.transactions.count) transactions for \(wallet.chain.rawValue)")
        } catch {
            logger.error("Failed to load transactions: \(error.localizedDescription)")
        }
    }

    /// Refresh the balance for the currently selected wallet.
    func refreshBalance() async {
        guard var wallet = selectedWallet, let repo = walletRepository else { return }

        do {
            wallet = try await repo.refreshBalance(for: wallet)
            if let index = wallets.firstIndex(where: { $0.id == wallet.id }) {
                wallets[index] = wallet
            }
            selectedWallet = wallet
            logger.info("Balance refreshed: \(wallet.balance) \(wallet.chain.nativeToken)")
        } catch {
            logger.error("Balance refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Send

    /// Estimate the fee for the current send form.
    func estimateFee() async {
        guard let useCase = sendCryptoUseCase,
              let amount = Decimal(string: sendAmount),
              !sendRecipient.isEmpty else {
            return
        }

        sendState = .estimating

        do {
            let cost = try await useCase.estimateCost(
                amount: amount,
                recipientAddress: sendRecipient,
                chain: selectedChain
            )

            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 6
            let feeStr = formatter.string(from: cost.fee as NSDecimalNumber) ?? "\(cost.fee)"
            sendState = .readyToSend(fee: "\(feeStr) \(selectedChain.nativeToken)")
        } catch {
            sendState = .error(AppError.from(error).localizedDescription)
        }
    }

    /// Execute the send transaction.
    func send() async {
        guard let useCase = sendCryptoUseCase,
              let amount = Decimal(string: sendAmount) else {
            sendState = .error("Invalid amount")
            return
        }

        sendState = .signing
        logger.info("Sending \(self.sendAmount) \(self.selectedChain.nativeToken) to \(self.sendRecipient.prefix(10))...")

        do {
            sendState = .broadcasting
            let tx = try await useCase.execute(
                amount: amount,
                recipientAddress: sendRecipient,
                chain: selectedChain,
                note: sendNote.isEmpty ? nil : sendNote
            )

            sendState = .success(txHash: tx.hash)
            transactions.insert(tx, at: 0)

            // Clear form
            sendRecipient = ""
            sendAmount = ""
            sendNote = ""

            // Refresh balance
            await refreshBalance()

            logger.info("Transaction sent: \(tx.shortHash)")
        } catch {
            sendState = .error(AppError.from(error).localizedDescription)
            logger.error("Send failed: \(error.localizedDescription)")
        }
    }

    /// Reset the send state.
    func resetSendState() {
        sendState = .idle
    }

    // MARK: - Computed

    /// Total portfolio value across all chains.
    var totalBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4

        guard let wallet = selectedWallet else { return "0.00" }
        return formatter.string(from: wallet.balance as NSDecimalNumber) ?? "0.00"
    }

    /// Formatted address for clipboard/sharing.
    var currentAddress: String {
        selectedWallet?.address ?? ""
    }
}
