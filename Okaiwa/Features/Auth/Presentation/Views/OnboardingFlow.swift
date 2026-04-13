import SwiftUI

/// Top-level onboarding flow — mirrors the `AppNavigation.kt` Android graph.
///
/// Drives the sequence:
///   Splash → Welcome → (Register | Login) → PhoneNumber → OTP → Main.
///
/// The country picker is presented as a modal sheet over the phone entry
/// screen, matching the Android bottom-sheet feel.
///
/// Both the PhoneNumber step (POST /v1/auth/register) and the OTP step
/// (POST /v1/auth/verify) talk to the deployed identity service via
/// [IdentityAuthService]. The session store is shared between the two
/// steps so the verify call can re-submit the phone hash stashed at
/// register time without asking for the number again.
@MainActor
public struct OnboardingFlow: View {
    public enum Step: Equatable, Hashable {
        case splash
        case welcome
        case phoneEntry(mode: PhoneEntryMode)
        case otpVerification(phoneDisplay: String)
        /// Post-OTP (or post-login on a fresh device) — the user picks
        /// a username + optional displayName / bio. Only shown once;
        /// the `profileSetupDone` flag in SessionStore makes subsequent
        /// cold launches skip straight to `.complete`.
        case profileSetup
        case complete
    }

    @State private var step: Step = .splash
    @State private var selectedCountry: Country = Countries.default
    @State private var showCountryPicker: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var phoneError: String?
    @State private var accountNotFoundForLogin: Bool = false
    @State private var pendingPhoneE164: String = ""
    @State private var otpError: String?

    // Shared singleton — must be the SAME instance every other
    // consumer (RemoteProfileRepository, IdentityAuthService) reaches
    // for, otherwise a `clear()` on one instance leaves stale tokens
    // in others' @Observable snapshots and the logout watchdog below
    // never fires.
    @State private var sessionStore = SessionStore.shared
    private let authService: IdentityAuthService
    private let profileRepository: RemoteProfileRepository

    let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let sessionStore = SessionStore.shared
        self._sessionStore = State(initialValue: sessionStore)
        self.authService = IdentityAuthService(sessionStore: sessionStore)
        self.profileRepository = RemoteProfileRepository.shared
    }

    public var body: some View {
        ZStack {
            switch step {
            case .splash:
                // Read the persisted session ONCE at splash time so the
                // entry route reflects whether the user is already
                // authenticated. Same routing matrix as Android's
                // SessionGateViewModel — single source of truth here.
                //
                // When the local `profileSetupDone` flag is false we
                // ALSO ask the server whether the account already has
                // a username (reinstall path). Without this check a
                // user whose local flag was wiped would be pushed
                // through ProfileSetup and hit HTTP 409 "username
                // taken" on the upcoming PUT — the bug this bootstrap
                // closes (mirror of okaiwa-android commit f650521).
                SplashView {
                    Task { await resolveSplashRoute() }
                }

            case .welcome:
                WelcomeView(
                    onCreateAccount: { step = .phoneEntry(mode: .register) },
                    onSignIn: { step = .phoneEntry(mode: .login) }
                )

            case .phoneEntry(let mode):
                PhoneNumberView(
                    mode: mode,
                    selectedCountry: $selectedCountry,
                    onBack: { step = .welcome },
                    onPickCountry: { showCountryPicker = true },
                    onContinue: { country, nationalNumber, _ in
                        let full = "\(country.dialCode)\(nationalNumber)"
                        pendingPhoneE164 = full
                        Task { await submitPhone(full, mode: mode) }
                    },
                    isLoading: isSubmitting,
                    errorMessage: phoneError,
                    accountNotFoundForLogin: accountNotFoundForLogin,
                    onCreateAccountFromLogin: {
                        accountNotFoundForLogin = false
                        Task { await submitPhone(pendingPhoneE164, mode: .register) }
                    }
                )

            case .otpVerification(let phoneDisplay):
                OtpVerificationView(
                    phoneNumberDisplay: phoneDisplay,
                    onBack: { step = .phoneEntry(mode: .register) },
                    onSubmit: { code in
                        Task { await submitOtp(code) }
                    },
                    onResend: {
                        // TODO: call authRepository.requestOtp again
                    },
                    isLoading: isSubmitting,
                    errorMessage: otpError
                )

            case .profileSetup:
                ProfileSetupView(
                    sessionStore: sessionStore,
                    onDone: {
                        step = .complete
                        onComplete()
                    }
                )

            case .complete:
                // The host ContentView is expected to replace the
                // onboarding flow with MainScaffold once onComplete
                // fires. If the host keeps the OnboardingFlow alive we
                // fall back to showing MainScaffold inline so the tab
                // bar still appears, mirroring the Android navigation
                // where OTP success pops to Screen.Main.
                MainScaffold { tab in
                    switch tab {
                    case .chats:
                        ConversationListView(
                            onNavigateToChat: { _ in /* TODO: push chat */ },
                            onNavigateToContacts: { /* TODO: push contacts */ }
                        )
                    case .wallet:
                        WalletOnboardingView(
                            onCreateWallet: { /* TODO: push seed-phrase flow */ },
                            onImportWallet: { /* TODO: push mnemonic import */ }
                        )
                    case .settings: SettingsTabPlaceholder()
                    case .profile:  ProfileView()
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        // Logout watchdog — when the SessionStore goes nil while we
        // are in .complete (i.e. the user tapped Déconnexion from
        // ProfileView, which calls RemoteProfileRepository.signOut →
        // sessionStore.clear()), flip back to .welcome instead of
        // letting MainScaffold re-render against a wiped session.
        // Mirrors `popUpTo(0) { inclusive = true }` on Android's
        // navController.
        .onChange(of: sessionStore.current) { _, newValue in
            if newValue == nil && step != .welcome && step != .splash {
                step = .welcome
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(
                onBack: { showCountryPicker = false },
                onSelect: { country in
                    selectedCountry = country
                    showCountryPicker = false
                }
            )
            .presentationBackground(OkaiwaColors.black)
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Identity service calls

    private func submitPhone(_ phoneE164: String, mode: PhoneEntryMode) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        phoneError = nil
        accountNotFoundForLogin = false

        do {
            switch mode {
            case .register:
                try await authService.register(phoneE164: phoneE164)
            case .login:
                try await authService.login(phoneE164: phoneE164)
            }
            isSubmitting = false
            step = .otpVerification(phoneDisplay: phoneE164)
        } catch AuthClientError.accountNotFound {
            isSubmitting = false
            accountNotFoundForLogin = true
        } catch let error as AppError {
            isSubmitting = false
            phoneError = error.errorDescription ?? L10n.string("phone_entry_generic_error")
        } catch {
            isSubmitting = false
            phoneError = error.localizedDescription
        }
    }

    private func submitOtp(_ code: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        otpError = nil

        do {
            try await authService.verify(code: code)

            // Server is the source of truth: if the account already
            // has a username, we MUST NOT push the user back through
            // ProfileSetup — they'd retype the same handle and hit a
            // 409. Pre-existing accounts go straight to Main (mirror
            // of okaiwa-android commit 14bf000).
            switch await profileRepository.fetchUsernameForBootstrap() {
            case .existing:
                sessionStore.markProfileSetupDone()
                isSubmitting = false
                step = .complete
                onComplete()
            case .newUser:
                isSubmitting = false
                step = .profileSetup
            case .authFailure:
                isSubmitting = false
                otpError = L10n.string("otp_session_expired")
            case .transientFailure:
                isSubmitting = false
                otpError = L10n.string("otp_network_error")
            }
        } catch let error as AppError {
            isSubmitting = false
            otpError = error.errorDescription ?? L10n.string("otp_generic_error")
        } catch {
            isSubmitting = false
            otpError = error.localizedDescription
        }
    }

    /// Splash routing matrix — mirrors `SessionGateViewModel.kt` on
    /// Android, including the async server check that closes the
    /// reinstall bug (local flag says "needs ProfileSetup" but the
    /// server already has the username — go straight to Main).
    ///
    ///   - session == nil                  → .welcome
    ///   - !session.isVerified             → .welcome
    ///   - session.profileSetupDone        → .complete
    ///   - else, ask the server:
    ///       - .existing → markProfileSetupDone + .complete
    ///       - .newUser → .profileSetup
    ///       - .authFailure → .welcome (clean re-auth)
    ///       - .transientFailure → .profileSetup (legacy fallback)
    private func resolveSplashRoute() async {
        guard let session = sessionStore.current, session.isVerified else {
            step = .welcome
            return
        }
        if session.profileSetupDone {
            step = .complete
            onComplete()
            return
        }
        switch await profileRepository.fetchUsernameForBootstrap() {
        case .existing:
            sessionStore.markProfileSetupDone()
            step = .complete
            onComplete()
        case .newUser:
            step = .profileSetup
        case .authFailure:
            step = .welcome
        case .transientFailure:
            step = .profileSetup
        }
    }
}
