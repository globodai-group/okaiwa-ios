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

            Text(L10n.key("app_name"))
                .font(OkaiwaTheme.Typography.largeTitle)
                .foregroundStyle(OkaiwaTheme.Colors.textPrimary)

            Text(L10n.key("legacy_login_tagline"))
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
            featureRow(
                icon: "lock.shield.fill",
                titleKey: "legacy_login_feature_encrypted_title",
                subtitleKey: "legacy_login_feature_encrypted_subtitle"
            )

            featureRow(
                icon: "creditcard.fill",
                titleKey: "legacy_login_feature_wallet_title",
                subtitleKey: "legacy_login_feature_wallet_subtitle"
            )

            featureRow(
                icon: "eye.slash.fill",
                titleKey: "legacy_login_feature_metadata_title",
                subtitleKey: "legacy_login_feature_metadata_subtitle"
            )

            Button {
                viewModel.startRegistration()
            } label: {
                Text(L10n.key("legacy_login_get_started"))
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
            Text(L10n.key("legacy_login_phone_title"))
                .font(OkaiwaTheme.Typography.title)

            Text(L10n.key("legacy_login_phone_subtitle"))
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: OkaiwaTheme.Spacing.xs) {
                // Country code — the "+33" is a neutral example and
                // not a translatable label, keep as a verbatim
                // LocalizedStringKey that bypasses the resource table.
                TextField("+33", text: $vm.countryCode)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .frame(width: 72)
                    .padding(OkaiwaTheme.Spacing.sm)
                    .background(OkaiwaTheme.Colors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.small))

                // Phone number
                TextField(L10n.key("legacy_login_phone_placeholder"), text: $vm.phoneNumber)
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
                    Text(L10n.key("legacy_login_send_code"))
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
            Text(L10n.key("legacy_login_verify_title"))
                .font(OkaiwaTheme.Typography.title)

            // Two `%@` placeholders — dial-code then national number —
            // so the translated copy can glue them with different
            // punctuation or a space if the locale demands it.
            Text(L10n.string("legacy_login_verify_subtitle_format", viewModel.countryCode, viewModel.phoneNumber))
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
                    Text(L10n.key("legacy_login_verify_cta"))
                        .font(OkaiwaTheme.Typography.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OkaiwaTheme.Spacing.xs)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .disabled(viewModel.isLoading || viewModel.verificationCode.count != 6)

            Button(L10n.string("legacy_login_resend_cta")) {
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
            Text(L10n.key("legacy_login_username_title"))
                .font(OkaiwaTheme.Typography.title)

            Text(L10n.key("legacy_login_username_subtitle"))
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)

            TextField(L10n.key("legacy_login_username_placeholder"), text: $vm.username)
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
                    Text(L10n.key("legacy_login_username_cta"))
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
            Text(L10n.key("legacy_login_footer_disclaimer"))
                .font(OkaiwaTheme.Typography.caption)
                .foregroundStyle(OkaiwaTheme.Colors.textTertiary)

            HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                Link(destination: URL(string: "https://okaiwa.io/terms")!) {
                    Text(L10n.key("legacy_login_footer_terms"))
                }
                Text(L10n.key("legacy_login_footer_and"))
                Link(destination: URL(string: "https://okaiwa.io/privacy")!) {
                    Text(L10n.key("legacy_login_footer_privacy"))
                }
            }
            .font(OkaiwaTheme.Typography.caption)
            .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
        }
        .padding(.bottom, OkaiwaTheme.Spacing.lg)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, titleKey: String, subtitleKey: String) -> some View {
        HStack(spacing: OkaiwaTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                Text(L10n.key(titleKey))
                    .font(OkaiwaTheme.Typography.headline)
                Text(L10n.key(subtitleKey))
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, OkaiwaTheme.Spacing.xs)
    }
}
