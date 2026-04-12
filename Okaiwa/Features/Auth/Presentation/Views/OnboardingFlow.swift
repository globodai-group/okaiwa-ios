import SwiftUI

/// Top-level onboarding flow — mirrors the `AppNavigation.kt` Android graph.
///
/// Drives the sequence:
///   Splash → Welcome → (Register | Login) → PhoneNumber → OTP → Main.
///
/// The country picker is presented as a modal sheet over the phone entry
/// screen, matching the Android bottom-sheet feel.
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
    let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
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
                        step = .otpVerification(phoneDisplay: full)
                    }
                )

            case .otpVerification(let phoneDisplay):
                OtpVerificationView(
                    phoneNumberDisplay: phoneDisplay,
                    onBack: { step = .phoneEntry(mode: .register) },
                    onSubmit: { _ in
                        step = .complete
                        onComplete()
                    },
                    onResend: {
                        // TODO: call authRepository.requestOtp again
                    }
                )

            case .complete:
                // Transient — the host ContentView swaps us out for MainTabView.
                Color.clear
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
}
