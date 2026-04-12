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
            Text("Wallet")
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

                    Text("Votre wallet crypto")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 12)

                    Text("Envoyez et recevez des cryptos directement dans vos conversations. Vos clés restent sur votre appareil.")
                        .font(.system(size: 15))
                        .foregroundStyle(OkaiwaColors.whiteDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)

                    Spacer()
                }

                VStack(spacing: 12) {
                    Button(action: onCreateWallet) {
                        Text("Créer un wallet")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(OkaiwaColors.lime)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button(action: onImportWallet) {
                        Text("Importer un wallet")
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
                .padding(.bottom, floatingBarInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }
}
