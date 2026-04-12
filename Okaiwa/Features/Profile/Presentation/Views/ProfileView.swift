import SwiftUI

/// Profile tab — Telegram-style identity card. Mirrors
/// `ProfileScreen.kt`.
///
/// Layout, top to bottom:
///   - Top bar: QR code icon (left), more-actions kebab (right).
///   - Avatar medallion + display name + Pro star + presence text.
///   - Three quick-action tiles: Photo, Modifier, Paramètres.
///   - Identity card: Mobile, Nom d'utilisateur, Bio.
///   - Publications / Publications archivées tab pills.
///   - Empty state with "Ajouter une publication" CTA.
public struct ProfileView: View {
    var onOpenSettings: () -> Void = {}
    var onOpenQrCode: () -> Void = {}
    var onEditProfile: () -> Void = {}
    var onPickAvatar: () -> Void = {}
    var onAddPublication: () -> Void = {}

    @Environment(\.floatingBarInset) private var floatingBarInset: CGFloat
    @ObservedObject private var repo = MockProfileRepository.shared
    @State private var selectedTab: PublicationTab = .active

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            if let profile = repo.profile {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 12)
                        avatarBlock(profile: profile)
                        Spacer().frame(height: 20)
                        quickActions
                        Spacer().frame(height: 20)
                        identityCard(profile: profile)
                        Spacer().frame(height: 20)
                        publicationTabs
                        Spacer().frame(height: 40)
                        emptyPublications
                        Spacer().frame(height: floatingBarInset + 16)
                    }
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }

    private var topBar: some View {
        HStack {
            Button(action: onOpenQrCode) {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            Spacer()
            Button(action: { /* TODO: action sheet */ }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
        }
    }

    private func avatarBlock(profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(OkaiwaColors.lime.opacity(0.18))
                .frame(width: 128, height: 128)
                .overlay(
                    Circle().stroke(OkaiwaColors.blackBorder, lineWidth: 2)
                )
                .overlay(
                    Text(profile.displayName.first.map { String($0).uppercased() } ?? "?")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(OkaiwaColors.lime)
                )
                .onTapGesture(perform: onPickAvatar)

            Spacer().frame(height: 16)

            HStack(spacing: 6) {
                Text(profile.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(OkaiwaColors.white)
                if profile.isVerified {
                    Image(systemName: "star.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(OkaiwaColors.lime)
                }
            }

            Spacer().frame(height: 2)

            Text(profile.isOnline ? "en ligne" : "hors ligne")
                .font(.system(size: 13))
                .foregroundStyle(profile.isOnline ? OkaiwaColors.lime : OkaiwaColors.muted)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickActionTile(systemIcon: "camera.fill", label: "Photo", action: onPickAvatar)
            QuickActionTile(systemIcon: "pencil", label: "Modifier", action: onEditProfile)
            QuickActionTile(systemIcon: "gearshape.fill", label: "Paramètres", action: onOpenSettings)
        }
        .padding(.horizontal, 16)
    }

    private func identityCard(profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Mobile", value: profile.phoneNumberE164)
            divider
            InfoRow(label: "Nom d'utilisateur", value: profile.username)
            if let bio = profile.bio, !bio.isEmpty {
                divider
                InfoRow(label: "Bio", value: bio)
            }
        }
        .background(OkaiwaColors.blackElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Rectangle()
            .fill(OkaiwaColors.blackBorder)
            .frame(height: 0.5)
    }

    private var publicationTabs: some View {
        HStack(spacing: 8) {
            TabPill(
                text: "Publications",
                isSelected: selectedTab == .active,
                action: { selectedTab = .active }
            )
            TabPill(
                text: "Publications archivées",
                isSelected: selectedTab == .archived,
                action: { selectedTab = .archived }
            )
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var emptyPublications: some View {
        VStack(spacing: 6) {
            Text("Aucune publication...")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Text("Publiez des photos et vidéos à afficher sur votre page de profil.")
                .font(.system(size: 12))
                .foregroundStyle(OkaiwaColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 20)

            Button(action: onAddPublication) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16))
                    Text("Ajouter une publication")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(OkaiwaColors.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(OkaiwaColors.lime)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private enum PublicationTab { case active, archived }

    private struct QuickActionTile: View {
        let systemIcon: String
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.lime)
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OkaiwaColors.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OkaiwaColors.blackElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private struct InfoRow: View {
        let label: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private struct TabPill: View {
        let text: String
        let isSelected: Bool
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? OkaiwaColors.lime : OkaiwaColors.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isSelected ? OkaiwaColors.lime.opacity(0.2) : OkaiwaColors.blackElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
