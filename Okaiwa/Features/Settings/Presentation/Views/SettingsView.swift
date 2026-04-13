// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

/// Settings screen with security score, privacy controls, and app preferences.
///
/// Features:
/// - Security score ring chart
/// - Actionable security recommendations
/// - Privacy, notification, and appearance settings
/// - Account management (export keys, delete account)
struct SettingsView: View {

    @State private var securityScore = SecurityScore.evaluate()
    @State private var showDeleteConfirmation = false
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            // Security Score
            securityScoreSection

            // Recommendations
            if !securityScore.recommendations.isEmpty {
                recommendationsSection
            }

            // Privacy
            privacySection

            // Notifications
            notificationsSection

            // Appearance
            appearanceSection

            // Account
            accountSection

            // About
            aboutSection
        }
        .navigationTitle(L10n.key("settings_nav_title"))
    }

    // MARK: - Security Score Section

    private var securityScoreSection: some View {
        Section {
            VStack(spacing: OkaiwaTheme.Spacing.md) {
                // Ring chart
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(OkaiwaTheme.Colors.surfaceSecondary, lineWidth: 12)
                        .frame(width: 120, height: 120)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: CGFloat(securityScore.percentage) / 100)
                        .stroke(
                            scoreColor,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                        .animation(OkaiwaTheme.Animation.slow, value: securityScore.percentage)

                    // Score text
                    VStack(spacing: 2) {
                        Text("\(securityScore.percentage)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor)

                        Text(securityScore.grade.label)
                            .font(OkaiwaTheme.Typography.caption2)
                            .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, OkaiwaTheme.Spacing.sm)

                // Criteria grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: OkaiwaTheme.Spacing.xs) {
                    ForEach(securityScore.criteria) { criterion in
                        HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                            Image(systemName: criterion.isPassed ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(criterion.isPassed ? OkaiwaTheme.Colors.success : OkaiwaTheme.Colors.destructive)

                            Text(criterion.name)
                                .font(OkaiwaTheme.Typography.caption)
                                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text(L10n.key("settings_section_security_score"))
        }
    }

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        Section {
            ForEach(securityScore.recommendations) { rec in
                HStack(spacing: OkaiwaTheme.Spacing.sm) {
                    Image(systemName: rec.icon)
                        .font(.title3)
                        .foregroundStyle(priorityColor(rec.priority))
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                        HStack {
                            Text(rec.name)
                                .font(OkaiwaTheme.Typography.headline)

                            Spacer()

                            Text(rec.priority.label)
                                .font(OkaiwaTheme.Typography.caption2)
                                .foregroundStyle(priorityColor(rec.priority))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(priorityColor(rec.priority).opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Text(rec.description)
                            .font(OkaiwaTheme.Typography.caption)
                            .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                    }
                }
                .padding(.vertical, OkaiwaTheme.Spacing.xxs)
            }
        } header: {
            Text(L10n.key("settings_section_recommendations"))
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            NavigationLink {
                // TODO: PrivacySettingsView — placeholder kept
                // non-localized until the real destination lands.
                Text(verbatim: "Privacy Settings")
            } label: {
                Label(L10n.key("settings_row_privacy"), systemImage: "hand.raised.fill")
            }

            NavigationLink {
                Text(verbatim: "Blocked Contacts")
            } label: {
                Label(L10n.key("settings_row_blocked"), systemImage: "nosign")
            }

            NavigationLink {
                Text(verbatim: "Screen Security Settings")
            } label: {
                Label(L10n.key("settings_row_screen_security"), systemImage: "eye.slash.fill")
            }

            NavigationLink {
                Text(verbatim: "Disappearing Messages Default")
            } label: {
                Label(L10n.key("settings_row_disappearing"), systemImage: "timer")
            }
        } header: {
            Text(L10n.key("settings_section_privacy"))
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                Text(verbatim: "Notification Settings")
            } label: {
                Label(L10n.key("settings_row_notifications"), systemImage: "bell.fill")
            }

            NavigationLink {
                Text(verbatim: "Sound Settings")
            } label: {
                Label(L10n.key("settings_row_sounds"), systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text(L10n.key("settings_section_notifications"))
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                Text(verbatim: "Theme Settings")
            } label: {
                Label(L10n.key("settings_row_appearance"), systemImage: "paintbrush.fill")
            }

            NavigationLink {
                Text(verbatim: "Chat Wallpaper")
            } label: {
                Label(L10n.key("settings_row_wallpaper"), systemImage: "photo.fill")
            }
        } header: {
            Text(L10n.key("settings_section_appearance"))
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            NavigationLink {
                Text(verbatim: "Linked Devices")
            } label: {
                Label(L10n.key("settings_row_linked_devices"), systemImage: "laptopcomputer.and.iphone")
            }

            Button {
                // Export identity keys
            } label: {
                Label(L10n.key("settings_row_export_keys"), systemImage: "key.fill")
                    .foregroundStyle(OkaiwaTheme.Colors.textPrimary)
            }

            Button {
                Task { await authViewModel.logout() }
            } label: {
                Label(L10n.key("settings_row_logout"), systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(OkaiwaTheme.Colors.warning)
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Label(L10n.key("settings_row_delete_account"), systemImage: "trash.fill")
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }
        } header: {
            Text(L10n.key("settings_section_account"))
        }
        .alert(L10n.key("settings_delete_alert_title"), isPresented: $showDeleteConfirmation) {
            Button(L10n.string("settings_delete_alert_cancel"), role: .cancel) {}
            Button(L10n.string("settings_delete_alert_confirm"), role: .destructive) {
                // Delete account flow
            }
        } message: {
            Text(L10n.key("settings_delete_alert_body"))
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text(L10n.key("settings_row_version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
            }

            NavigationLink {
                Text(verbatim: "Open Source Licenses")
            } label: {
                Text(L10n.key("settings_row_licenses"))
            }

            Link(destination: URL(string: "https://okaiwa.io/privacy")!) {
                Text(L10n.key("settings_row_privacy_link"))
            }
            Link(destination: URL(string: "https://okaiwa.io/terms")!) {
                Text(L10n.key("settings_row_terms_link"))
            }
        } header: {
            Text(L10n.key("settings_section_about"))
        } footer: {
            Text(L10n.key("settings_about_footer"))
                .font(OkaiwaTheme.Typography.caption2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, OkaiwaTheme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    private var scoreColor: Color {
        switch securityScore.grade {
        case .excellent: return OkaiwaTheme.Colors.success
        case .good: return OkaiwaTheme.Colors.primaryFallback
        case .fair: return OkaiwaTheme.Colors.warning
        case .poor: return OkaiwaTheme.Colors.destructive
        }
    }

    private func priorityColor(_ priority: SecurityScore.Priority) -> Color {
        switch priority {
        case .critical: return OkaiwaTheme.Colors.destructive
        case .high: return OkaiwaTheme.Colors.warning
        case .medium: return OkaiwaTheme.Colors.primaryFallback
        }
    }
}
