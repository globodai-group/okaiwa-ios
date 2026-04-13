import SwiftUI

/// Welcome screen — mirrors `WelcomeScreen.kt` on Android.
///
/// Two primary actions on a dark canvas:
///   - "Créer un compte" — filled lime button.
///   - "Se connecter"    — outlined lime button.
public struct WelcomeView: View {
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    public init(onCreateAccount: @escaping () -> Void, onSignIn: @escaping () -> Void) {
        self.onCreateAccount = onCreateAccount
        self.onSignIn = onSignIn
    }

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            // Logo + wordmark — centered upper block.
            VStack(spacing: 12) {
                Image("OkaiwaLogoForeground")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)

                Text(L10n.key("app_wordmark"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(OkaiwaColors.white)
                    .tracking(6)

                Text(L10n.key("welcome_tagline"))
                    .font(.system(size: 16))
                    .foregroundStyle(OkaiwaColors.whiteDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 8)
            }
            .offset(y: -80)

            // CTAs — pinned to the bottom.
            VStack(spacing: 12) {
                Button(action: onCreateAccount) {
                    Text(L10n.key("welcome_create_account_button"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(OkaiwaColors.lime)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button(action: onSignIn) {
                    Text(L10n.key("welcome_sign_in_button"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.lime)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(OkaiwaColors.lime, lineWidth: 1.5)
                        )
                }

                Text(L10n.key("welcome_legal_disclaimer"))
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 32)
        }
    }
}
