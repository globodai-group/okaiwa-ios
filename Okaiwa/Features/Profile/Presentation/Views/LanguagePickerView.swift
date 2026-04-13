// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI
import OkaiwaCore

/// Manual language override — presented as a Profile row and mirrored on
/// Android under the same key (`profile_language_row`).
///
/// Shows every shipped locale plus a "Follow system" option at the top.
/// Tapping a row calls `LocaleManager.shared.setLocale(...)` and
/// dismisses. The `.id(effectiveLocale.identifier)` on the root ties
/// every `LocalizedStringKey` to the switch — on tap the entire app
/// re-renders with the new copy, no relaunch required.
public struct LanguagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocaleManager.self) private var manager

    public init() {}

    public var body: some View {
        ZStack {
            OkaiwaColors.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 0) {
                        row(
                            labelKey: "language_picker_system",
                            isSelected: manager.selected == nil,
                            action: {
                                manager.setLocale(nil)
                                dismiss()
                            }
                        )
                        divider
                        ForEach(SupportedLocale.allCases) { locale in
                            row(
                                labelKey: locale.displayNameKey,
                                isSelected: manager.selected == locale,
                                action: {
                                    manager.setLocale(locale)
                                    dismiss()
                                }
                            )
                            if locale != SupportedLocale.allCases.last {
                                divider
                            }
                        }
                    }
                    .background(OkaiwaColors.blackElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            Text(L10n.key("language_picker_title"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Spacer()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(OkaiwaColors.blackBorder)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func row(labelKey: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(L10n.key(labelKey))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OkaiwaColors.lime)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
