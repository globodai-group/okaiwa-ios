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
        .navigationTitle("Settings")
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
            Text("Security Score")
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
            Text("Recommendations")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            NavigationLink {
                Text("Privacy Settings")
            } label: {
                Label("Privacy", systemImage: "hand.raised.fill")
            }

            NavigationLink {
                Text("Blocked Contacts")
            } label: {
                Label("Blocked", systemImage: "nosign")
            }

            NavigationLink {
                Text("Screen Security Settings")
            } label: {
                Label("Screen Security", systemImage: "eye.slash.fill")
            }

            NavigationLink {
                Text("Disappearing Messages Default")
            } label: {
                Label("Disappearing Messages", systemImage: "timer")
            }
        } header: {
            Text("Privacy & Security")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                Text("Notification Settings")
            } label: {
                Label("Notifications", systemImage: "bell.fill")
            }

            NavigationLink {
                Text("Sound Settings")
            } label: {
                Label("Sounds", systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text("Notifications")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            NavigationLink {
                Text("Theme Settings")
            } label: {
                Label("Appearance", systemImage: "paintbrush.fill")
            }

            NavigationLink {
                Text("Chat Wallpaper")
            } label: {
                Label("Wallpaper", systemImage: "photo.fill")
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            NavigationLink {
                Text("Linked Devices")
            } label: {
                Label("Linked Devices", systemImage: "laptopcomputer.and.iphone")
            }

            Button {
                // Export identity keys
            } label: {
                Label("Export Identity Keys", systemImage: "key.fill")
                    .foregroundStyle(OkaiwaTheme.Colors.textPrimary)
            }

            Button {
                Task { await authViewModel.logout() }
            } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(OkaiwaTheme.Colors.warning)
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Account", systemImage: "trash.fill")
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }
        } header: {
            Text("Account")
        }
        .alert("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                // Delete account flow
            }
        } message: {
            Text("This will permanently delete your account, all messages, and wallet data. This action cannot be undone.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
            }

            NavigationLink {
                Text("Open Source Licenses")
            } label: {
                Text("Licenses")
            }

            Link("Privacy Policy", destination: URL(string: "https://okaiwa.io/privacy")!)
            Link("Terms of Service", destination: URL(string: "https://okaiwa.io/terms")!)
        } header: {
            Text("About")
        } footer: {
            Text("Okaiwa is open source software licensed under AGPLv3.\nCopyright 2026 Globodai FZCO.")
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
