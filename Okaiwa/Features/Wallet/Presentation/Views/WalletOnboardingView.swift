import SwiftUI

/// Wallet tab entry state shown while no wallet exists — mirrors
/// `WalletOnboardingScreen.kt` on Android.
///
/// Two primary actions (create / import) sit above the floating tab bar,
/// offset via `@Environment(\.floatingBarInset)` so the CTAs never hide
/// behind it.
public struct WalletOnboardingView: View {
    let onCreateWallet: () -> Void
    let onImportWallet: () -> Void

    @Environment(\.floatingBarInset) private var floatingBarInset: CGFloat

    public init(
        onCreateWallet: @escaping () -> Void,
        onImportWallet: @escaping () -> Void
    ) {
        self.onCreateWallet = onCreateWallet
        self.onImportWallet = onImportWallet
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.key("wallet_title"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .padding(.top, 16)

            ZStack {
                VStack(spacing: 0) {
                    Spacer()

                    Circle()
                        .fill(OkaiwaColors.lime.opacity(0.12))
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(OkaiwaColors.lime)
                        )

                    Spacer().frame(height: 24)

                    Text(L10n.key("wallet_onboarding_title"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 12)

                    Text(L10n.key("wallet_onboarding_subtitle"))
                        .font(.system(size: 15))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)

                    Spacer()
                }

                VStack(spacing: 12) {
                    Button(action: onCreateWallet) {
                        Text(L10n.key("wallet_onboarding_create_cta"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OkaiwaColors.lime)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button(action: onImportWallet) {
                        Text(L10n.key("wallet_onboarding_import_cta"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.lime)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(OkaiwaColors.lime, lineWidth: 1.5)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .bottom)
                // Extra 16 pt gutter above the floating tab bar — the
                // inset alone had the CTAs visually kissing the bar.
                .padding(.bottom, floatingBarInset + 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }
}
