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
    // Switched from MockProfileRepository (hardcoded Kevin / @asmista
    // / Globodai) to the live repo that fetches GET /v1/profile/me
    // on first appear. See RemoteProfileRepository for the network
    // strategy and the security review on okaiwa-android@386d11d for
    // why the bind moved.
    @ObservedObject private var repo = RemoteProfileRepository.shared
    @State private var selectedTab: PublicationTab = .active
    @State private var showLanguagePicker: Bool = false

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
                        Spacer().frame(height: 16)
                        languageRow
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
        .task { repo.start() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView()
                .presentationBackground(OkaiwaColors.black)
                .presentationDragIndicator(.visible)
        }
    }

    /// Language row — identity-card companion that opens the
    /// `LanguagePickerView`. Same visual weight as the identity card
    /// rows so the block reads as a continuation of the user's
    /// preferences rather than a system setting.
    private var languageRow: some View {
        Button {
            showLanguagePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(OkaiwaColors.lime)
                    .frame(width: 24)
                Text(L10n.key("profile_language_row"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(OkaiwaColors.blackElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack {
            Button(action: onOpenQrCode) {
                Image(systemName: "qrcode")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            .accessibilityLabel(L10n.string("profile_top_bar_qr_cd"))

            Spacer()

            // Native SwiftUI Menu = the iOS analog of M3 DropdownMenu.
            // Anchored to the kebab IconButton; iOS handles placement +
            // tap-outside dismissal automatically.
            Menu {
                Button(role: .destructive, action: { repo.signOut() }) {
                    Label(L10n.string("profile_more_menu_logout"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            .accessibilityLabel(L10n.string("profile_top_bar_more_cd"))
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

            Text(L10n.key(profile.isOnline ? "profile_presence_online" : "profile_presence_offline"))
                .font(.system(size: 13))
                .foregroundStyle(profile.isOnline ? OkaiwaColors.lime : OkaiwaColors.muted)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            QuickActionTile(systemIcon: "camera.fill", labelKey: "profile_action_photo", action: onPickAvatar)
            QuickActionTile(systemIcon: "pencil", labelKey: "profile_action_edit", action: onEditProfile)
            QuickActionTile(systemIcon: "gearshape.fill", labelKey: "profile_action_settings", action: onOpenSettings)
        }
        .padding(.horizontal, 16)
    }

    private func identityCard(profile: UserProfile) -> some View {
        VStack(spacing: 0) {
            InfoRow(labelKey: "profile_info_mobile", value: profile.phoneNumberE164)
            divider
            InfoRow(labelKey: "profile_info_username", value: profile.username)
            if let bio = profile.bio, !bio.isEmpty {
                divider
                InfoRow(labelKey: "profile_info_bio", value: bio)
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
                textKey: "profile_tab_publications",
                isSelected: selectedTab == .active,
                action: { selectedTab = .active }
            )
            TabPill(
                textKey: "profile_tab_publications_archived",
                isSelected: selectedTab == .archived,
                action: { selectedTab = .archived }
            )
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var emptyPublications: some View {
        VStack(spacing: 6) {
            Text(L10n.key("profile_empty_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Text(L10n.key("profile_empty_subtitle"))
                .font(.system(size: 12))
                .foregroundStyle(OkaiwaColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer().frame(height: 20)

            Button(action: onAddPublication) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16))
                    Text(L10n.key("profile_empty_cta"))
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
        let labelKey: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 6) {
                    Image(systemName: systemIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.lime)
                    Text(L10n.key(labelKey))
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
        let labelKey: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                Text(L10n.key(labelKey))
                    .font(.system(size: 12))
                    .foregroundStyle(OkaiwaColors.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private struct TabPill: View {
        let textKey: String
        let isSelected: Bool
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(L10n.key(textKey))
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
