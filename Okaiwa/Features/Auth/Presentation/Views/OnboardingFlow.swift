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
        case complete
    }

    @State private var step: Step = .splash
    @State private var selectedCountry: Country = Countries.default
    @State private var showCountryPicker: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var phoneError: String?
    @State private var otpError: String?

    @State private var sessionStore = SessionStore()
    private let authService: IdentityAuthService

    let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let sessionStore = SessionStore()
        self._sessionStore = State(initialValue: sessionStore)
        self.authService = IdentityAuthService(sessionStore: sessionStore)
    }

    public var body: some View {
        ZStack {
            switch step {
            case .splash:
                SplashView { step = .welcome }

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
                        Task { await submitPhone(full) }
                    },
                    isLoading: isSubmitting,
                    errorMessage: phoneError
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

    private func submitPhone(_ phoneE164: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        phoneError = nil

        do {
            try await authService.register(phoneE164: phoneE164)
            isSubmitting = false
            step = .otpVerification(phoneDisplay: phoneE164)
        } catch let error as AppError {
            isSubmitting = false
            phoneError = error.errorDescription ?? "Échec de l'inscription"
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
            isSubmitting = false
            step = .complete
            onComplete()
        } catch let error as AppError {
            isSubmitting = false
            otpError = error.errorDescription ?? "Code incorrect"
        } catch {
            isSubmitting = false
            otpError = error.localizedDescription
        }
    }
}
