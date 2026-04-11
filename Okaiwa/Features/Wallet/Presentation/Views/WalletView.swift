// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

/// Wallet screen — displays balances, chain selector, and transaction history.
///
/// Features:
/// - Card per blockchain with balance
/// - Send / Receive actions
/// - Transaction history list
/// - Pull-to-refresh for balance updates
struct WalletView: View {

    @State private var viewModel = WalletViewModel()
    @State private var showSendSheet = false
    @State private var showReceiveSheet = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(spacing: OkaiwaTheme.Spacing.md) {
                // Chain selector
                chainSelector

                // Balance card
                balanceCard

                // Action buttons
                actionButtons

                // Transaction history
                transactionSection
            }
            .padding(OkaiwaTheme.Spacing.md)
        }
        .navigationTitle("Wallet")
        .task {
            await viewModel.loadWallets()
        }
        .refreshable {
            await viewModel.refreshBalance()
        }
        .sheet(isPresented: $showSendSheet) {
            sendSheet
        }
        .sheet(isPresented: $showReceiveSheet) {
            receiveSheet
        }
    }

    // MARK: - Chain Selector

    private var chainSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OkaiwaTheme.Spacing.xs) {
                ForEach(Wallet.Chain.allCases, id: \.self) { chain in
                    Button {
                        withAnimation(OkaiwaTheme.Animation.standard) {
                            viewModel.selectedChain = chain
                        }
                    } label: {
                        HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                            Image(systemName: chain.iconName)
                                .font(.system(size: 14))

                            Text(chain.displayName)
                                .font(OkaiwaTheme.Typography.caption)
                        }
                        .padding(.horizontal, OkaiwaTheme.Spacing.sm)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                        .background(
                            viewModel.selectedChain == chain
                                ? OkaiwaTheme.Colors.primaryFallback
                                : OkaiwaTheme.Colors.surfaceSecondary
                        )
                        .foregroundStyle(
                            viewModel.selectedChain == chain
                                ? .white
                                : OkaiwaTheme.Colors.textPrimary
                        )
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(spacing: OkaiwaTheme.Spacing.sm) {
            // Chain icon and name
            HStack {
                Image(systemName: viewModel.selectedChain.iconName)
                    .font(.title2)
                    .foregroundStyle(.white)

                Text(viewModel.selectedChain.displayName)
                    .font(OkaiwaTheme.Typography.headline)
                    .foregroundStyle(.white)

                Spacer()

                // Refresh indicator
                if viewModel.loadState == .loading {
                    ProgressView()
                        .tint(.white)
                }
            }

            // Balance
            VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                Text(viewModel.totalBalance)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(viewModel.selectedChain.nativeToken)
                    .font(OkaiwaTheme.Typography.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Address
            if let wallet = viewModel.selectedWallet {
                HStack {
                    Text(wallet.shortAddress)
                        .font(OkaiwaTheme.Typography.monoSmall)
                        .foregroundStyle(.white.opacity(0.6))

                    Button {
                        UIPasteboard.general.string = wallet.address
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Token balances
            if let wallet = viewModel.selectedWallet, !wallet.tokenBalances.isEmpty {
                Divider()
                    .background(.white.opacity(0.2))

                ForEach(wallet.tokenBalances) { token in
                    HStack {
                        Text(token.symbol)
                            .font(OkaiwaTheme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.8))

                        Spacer()

                        Text("\(token.balance)")
                            .font(OkaiwaTheme.Typography.mono)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(OkaiwaTheme.Spacing.lg)
        .background(
            LinearGradient(
                colors: [
                    OkaiwaTheme.Colors.primaryFallback,
                    OkaiwaTheme.Colors.accentFallback
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.large))
        .okaiwaShadow(OkaiwaTheme.Shadows.medium)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: OkaiwaTheme.Spacing.md) {
            Button {
                showSendSheet = true
            } label: {
                Label("Send", systemImage: "arrow.up.circle.fill")
                    .font(OkaiwaTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OkaiwaTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)

            Button {
                showReceiveSheet = true
            } label: {
                Label("Receive", systemImage: "arrow.down.circle.fill")
                    .font(OkaiwaTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OkaiwaTheme.Spacing.sm)
            }
            .buttonStyle(.bordered)
            .tint(OkaiwaTheme.Colors.primaryFallback)
        }
    }

    // MARK: - Transaction Section

    private var transactionSection: some View {
        VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.sm) {
            Text("Recent Transactions")
                .font(OkaiwaTheme.Typography.headline)

            if viewModel.transactions.isEmpty {
                VStack(spacing: OkaiwaTheme.Spacing.sm) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(OkaiwaTheme.Colors.textTertiary)

                    Text("No transactions yet")
                        .font(OkaiwaTheme.Typography.callout)
                        .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OkaiwaTheme.Spacing.xxl)
            } else {
                ForEach(viewModel.transactions) { tx in
                    TransactionRow(
                        transaction: tx,
                        walletAddress: viewModel.currentAddress
                    )
                    .onTapGesture {
                        router.navigate(to: .transactionDetails(hash: tx.hash))
                    }

                    if tx.id != viewModel.transactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(OkaiwaTheme.Spacing.md)
        .background(OkaiwaTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.medium))
        .okaiwaShadow(OkaiwaTheme.Shadows.small)
    }

    // MARK: - Send Sheet

    private var sendSheet: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Address or ENS name", text: $viewModel.sendRecipient)
                        .font(OkaiwaTheme.Typography.mono)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Amount") {
                    HStack {
                        TextField("0.00", text: $viewModel.sendAmount)
                            .keyboardType(.decimalPad)

                        Text(viewModel.selectedChain.nativeToken)
                            .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                    }
                }

                Section("Note (optional)") {
                    TextField("What's this for?", text: $viewModel.sendNote)
                }

                if case .readyToSend(let fee) = viewModel.sendState {
                    Section("Estimated Fee") {
                        Text(fee)
                            .font(OkaiwaTheme.Typography.mono)
                    }
                }

                if case .error(let message) = viewModel.sendState {
                    Section {
                        Text(message)
                            .foregroundStyle(OkaiwaTheme.Colors.destructive)
                    }
                }
            }
            .navigationTitle("Send \(viewModel.selectedChain.nativeToken)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSendSheet = false
                        viewModel.resetSendState()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await viewModel.send() }
                    }
                    .disabled(viewModel.sendRecipient.isEmpty || viewModel.sendAmount.isEmpty)
                }
            }
            .onChange(of: viewModel.sendAmount) { _, _ in
                Task { await viewModel.estimateFee() }
            }
            .onChange(of: viewModel.sendState) { _, newState in
                if case .success = newState {
                    showSendSheet = false
                    viewModel.resetSendState()
                }
            }
        }
    }

    // MARK: - Receive Sheet

    private var receiveSheet: some View {
        NavigationStack {
            VStack(spacing: OkaiwaTheme.Spacing.xl) {
                Spacer()

                // QR code placeholder
                RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.medium)
                    .fill(OkaiwaTheme.Colors.surfaceSecondary)
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.system(size: 100))
                            .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
                    }

                // Address
                VStack(spacing: OkaiwaTheme.Spacing.xs) {
                    Text(viewModel.selectedChain.displayName)
                        .font(OkaiwaTheme.Typography.headline)

                    Text(viewModel.currentAddress)
                        .font(OkaiwaTheme.Typography.monoSmall)
                        .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OkaiwaTheme.Spacing.xl)
                }

                Button {
                    UIPasteboard.general.string = viewModel.currentAddress
                } label: {
                    Label("Copy Address", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(OkaiwaTheme.Colors.primaryFallback)

                Spacer()
            }
            .navigationTitle("Receive \(viewModel.selectedChain.nativeToken)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showReceiveSheet = false
                    }
                }
            }
        }
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {

    let transaction: CryptoTransaction
    let walletAddress: String

    var body: some View {
        HStack(spacing: OkaiwaTheme.Spacing.sm) {
            // Direction icon
            ZStack {
                Circle()
                    .fill(directionColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: directionIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(directionColor)
            }

            // Details
            VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                Text(directionLabel)
                    .font(OkaiwaTheme.Typography.headline)

                Text(transaction.shortHash)
                    .font(OkaiwaTheme.Typography.monoSmall)
                    .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
            }

            Spacer()

            // Amount and status
            VStack(alignment: .trailing, spacing: OkaiwaTheme.Spacing.xxs) {
                Text("\(directionSign)\(transaction.displayAmount) \(transaction.token)")
                    .font(OkaiwaTheme.Typography.headline)
                    .foregroundStyle(directionColor)

                HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                    if transaction.isPending {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                    Text(transaction.status.rawValue.capitalized)
                        .font(OkaiwaTheme.Typography.caption2)
                        .foregroundStyle(statusColor)
                }
            }
        }
        .padding(.vertical, OkaiwaTheme.Spacing.xxs)
    }

    // MARK: - Computed

    private var direction: CryptoTransaction.Direction {
        transaction.direction(for: walletAddress)
    }

    private var directionIcon: String {
        direction == .sent ? "arrow.up.right" : "arrow.down.left"
    }

    private var directionColor: Color {
        direction == .sent ? OkaiwaTheme.Colors.destructive : OkaiwaTheme.Colors.success
    }

    private var directionLabel: String {
        direction == .sent ? "Sent" : "Received"
    }

    private var directionSign: String {
        direction == .sent ? "-" : "+"
    }

    private var statusColor: Color {
        switch transaction.status {
        case .confirmed: return OkaiwaTheme.Colors.success
        case .pending, .preparing: return OkaiwaTheme.Colors.warning
        case .failed: return OkaiwaTheme.Colors.destructive
        case .replaced: return OkaiwaTheme.Colors.textTertiary
        }
    }
}
