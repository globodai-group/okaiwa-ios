import SwiftUI

/// Profile tab — mirrors `ProfileScreen.kt`. Placeholder content until
/// the identity service is wired up end-to-end.
public struct ProfileView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Profil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .padding(.top, 16)

            Spacer().frame(height: 40)

            Circle()
                .fill(OkaiwaColors.blackElevated)
                .frame(width: 96, height: 96)
                .overlay(
                    Circle().stroke(OkaiwaColors.blackBorder, lineWidth: 1)
                )
                .overlay(
                    Text("?")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(OkaiwaColors.muted)
                )

            Spacer().frame(height: 20)

            Text("Non connecté")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)

            Spacer().frame(height: 4)

            Text("Votre profil sera disponible ici")
                .font(.system(size: 13))
                .foregroundStyle(OkaiwaColors.muted)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }
}
