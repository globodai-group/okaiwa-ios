// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

/// Login and registration view.
///
/// Three-step flow:
/// 1. Phone number entry with country code selector
/// 2. SMS verification code entry
/// 3. Username selection
struct LoginView: View {

    @Environment(AuthViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            ZStack {
                OkaiwaTheme.Colors.surface
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Logo and tagline
                    headerSection

                    Spacer()

                    // Dynamic content based on auth state
                    contentSection

                    Spacer()

                    // Footer
                    footerSection
                }
                .padding(.horizontal, OkaiwaTheme.Spacing.xl)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: OkaiwaTheme.Spacing.sm) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
                .padding(.top, OkaiwaTheme.Spacing.xxxl)

            Text("Okaiwa")
                .font(OkaiwaTheme.Typography.largeTitle)
                .foregroundStyle(OkaiwaTheme.Colors.textPrimary)

            Text("Secure Messenger & Wallet")
                .font(OkaiwaTheme.Typography.subheadline)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        @Bindable var vm = viewModel

        switch viewModel.state {
        case .idle:
            welcomeContent

        case .enteringPhone:
            phoneEntryContent

        case .verifyingCode:
            codeVerificationContent

        case .choosingUsername:
            usernameContent

        case .authenticated:
            // Should not be visible — ContentView switches to MainTabView
            EmptyView()

        case .error:
            phoneEntryContent
        }
    }

    // MARK: - Welcome

    private var welcomeContent: some View {
        VStack(spacing: OkaiwaTheme.Spacing.lg) {
            featureRow(icon: "lock.shield.fill", title: "End-to-End Encrypted",
                       subtitle: "Messages secured with the Signal Protocol")

            featureRow(icon: "creditcard.fill", title: "Built-in Wallet",
                       subtitle: "Send and receive crypto without leaving the chat")

            featureRow(icon: "eye.slash.fill", title: "No Metadata Leaks",
                       subtitle: "Sealed sender and minimal server state")

            Button {
                viewModel.startRegistration()
            } label: {
                Text("Get Started")
                    .font(OkaiwaTheme.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OkaiwaTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .padding(.top, OkaiwaTheme.Spacing.lg)
        }
    }

    // MARK: - Phone Entry

    private var phoneEntryContent: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: OkaiwaTheme.Spacing.lg) {
            Text("Enter your phone number")
                .font(OkaiwaTheme.Typography.title)

            Text("We'll send you a verification code via SMS. Your phone number is hashed before leaving your device.")
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: OkaiwaTheme.Spacing.xs) {
                // Country code
                TextField("+33", text: $vm.countryCode)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .frame(width: 72)
                    .padding(OkaiwaTheme.Spacing.sm)
                    .background(OkaiwaTheme.Colors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.small))

                // Phone number
                TextField("Phone number", text: $vm.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(OkaiwaTheme.Spacing.sm)
                    .background(OkaiwaTheme.Colors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.small))
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }

            Button {
                Task {
                    await viewModel.requestVerificationCode()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                } else {
                    Text("Send Code")
                        .font(OkaiwaTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .disabled(viewModel.isLoading || viewModel.phoneNumber.isEmpty)
        }
    }

    // MARK: - Code Verification

    private var codeVerificationContent: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: OkaiwaTheme.Spacing.lg) {
            Text("Verify your number")
                .font(OkaiwaTheme.Typography.title)

            Text("Enter the 6-digit code sent to \(viewModel.countryCode)\(viewModel.phoneNumber)")
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $vm.verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(OkaiwaTheme.Typography.mono)
                .padding(OkaiwaTheme.Spacing.md)
                .background(OkaiwaTheme.Colors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.small))

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }

            Button {
                Task {
                    await viewModel.verifyCode()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                } else {
                    Text("Verify")
                        .font(OkaiwaTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .disabled(viewModel.isLoading || viewModel.verificationCode.count != 6)

            Button("Resend Code") {
                Task {
                    await viewModel.requestVerificationCode()
                }
            }
            .font(OkaiwaTheme.Typography.callout)
            .tint(OkaiwaTheme.Colors.primaryFallback)
        }
    }

    // MARK: - Username

    private var usernameContent: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: OkaiwaTheme.Spacing.lg) {
            Text("Choose a username")
                .font(OkaiwaTheme.Typography.title)

            Text("This is how others will find you on Okaiwa.")
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)

            TextField("username", text: $vm.username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(OkaiwaTheme.Spacing.sm)
                .background(OkaiwaTheme.Colors.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.small))

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }

            Button {
                Task {
                    await viewModel.setUsername()
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                } else {
                    Text("Continue")
                        .font(OkaiwaTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .disabled(viewModel.isLoading || viewModel.username.count < 3)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: OkaiwaTheme.Spacing.xxs) {
            Text("By continuing, you agree to our")
                .font(OkaiwaTheme.Typography.caption)
                .foregroundStyle(OkaiwaTheme.Colors.textTertiary)

            HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                Link("Terms of Service", destination: URL(string: "https://okaiwa.io/terms")!)
                Text("and")
                Link("Privacy Policy", destination: URL(string: "https://okaiwa.io/privacy")!)
            }
            .font(OkaiwaTheme.Typography.caption)
            .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
        }
        .padding(.bottom, OkaiwaTheme.Spacing.lg)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: OkaiwaTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                Text(title)
                    .font(OkaiwaTheme.Typography.headline)
                Text(subtitle)
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, OkaiwaTheme.Spacing.xs)
    }
}
