// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import SwiftUI
import Observation

/// Runtime locale override for the Okaiwa app.
///
/// iOS exposes the device's preferred language through
/// `Bundle.main.preferredLocalizations`, which SwiftUI consults when a
/// `LocalizedStringKey` or `String(localized:)` is resolved. That lookup
/// is baked in at process launch and can't be swapped live. What we CAN
/// do is override the `\.locale` environment value at the root of the
/// view tree so SwiftUI reloads the in-memory copy the next time it
/// reads a localized string.
///
/// Contract:
///   - `current` reflects the user's preference (nil = follow system).
///   - Written to UserDefaults under `okaiwa.locale.override`.
///   - `effectiveLocale` resolves to the concrete `Locale` used for the
///     SwiftUI environment injection — either the user's pick or the
///     system default.
///
/// The two locales we ship today are French and English. Extending this
/// to a new locale is mechanical: add the `.lproj` folder to both
/// `OkaiwaCore/Resources` and `OkaiwaFeatures/Resources`, add a case to
/// `SupportedLocale`, and add a row to `LanguagePickerView`. No other
/// site needs to know about the new language.
@MainActor
@Observable
public final class LocaleManager {
    public static let shared = LocaleManager()

    private static let defaultsKey = "okaiwa.locale.override"

    /// User-selected locale. `nil` means "follow the system" — the
    /// initial state for every fresh install.
    public private(set) var selected: SupportedLocale?

    /// The concrete `Locale` that should be pushed into SwiftUI's
    /// environment. Falls back to the first preferred localization
    /// advertised by the bundle (iOS's resolved match between the
    /// device language and our supported set).
    public var effectiveLocale: Locale {
        if let selected {
            return Locale(identifier: selected.identifier)
        }
        // Resolved against the on-device preference matrix — when the
        // system is French and we ship fr, this returns fr; when the
        // system is Spanish and we ship only en/fr, it falls back to
        // the development base (English).
        if let preferred = Bundle.main.preferredLocalizations.first {
            return Locale(identifier: preferred)
        }
        return Locale(identifier: "en")
    }

    /// The display language the picker should show as "currently on".
    /// Maps back to `SupportedLocale` when the resolved locale is one
    /// of our shipped options; otherwise returns `nil` so the picker
    /// highlights the "Follow system" row.
    public var activeLanguage: SupportedLocale? {
        if let selected { return selected }
        let code = effectiveLocale.language.languageCode?.identifier ?? "en"
        return SupportedLocale(languageCode: code)
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.defaultsKey),
           let match = SupportedLocale(identifier: stored) {
            self.selected = match
        } else {
            self.selected = nil
        }
    }

    /// Set the override and persist it. Passing `nil` restores the
    /// "follow system" default and removes the key.
    public func setLocale(_ locale: SupportedLocale?) {
        self.selected = locale
        if let locale {
            UserDefaults.standard.set(locale.identifier, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
}

/// Enumeration of the app's shipped locales. Extend this alongside the
/// `.lproj` folders — the picker reads `allCases`, so adding a new case
/// wires itself into the UI.
public enum SupportedLocale: String, CaseIterable, Identifiable, Sendable {
    case french = "fr"
    case english = "en"

    public var id: String { rawValue }
    public var identifier: String { rawValue }

    init?(identifier: String) {
        self.init(rawValue: identifier)
    }

    init?(languageCode: String) {
        self.init(rawValue: languageCode)
    }

    /// Key consumed by the LanguagePickerView — resolves to the
    /// locale's English-side label when shown in English and the
    /// French-side label when shown in French.
    public var displayNameKey: String {
        switch self {
        case .french: return "language_picker_french"
        case .english: return "language_picker_english"
        }
    }
}

// MARK: - SwiftUI glue

public struct OkaiwaLocaleRoot<Content: View>: View {
    @Environment(LocaleManager.self) private var manager
    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.locale, manager.effectiveLocale)
            // `.id(...)` forces a rebuild of the subtree when the
            // picker flips, ensuring every `LocalizedStringKey` is
            // re-evaluated against the new locale the SAME frame.
            // Without it, views that cached a string at init time
            // (labels inside .buttonStyle, static `Text` in structs)
            // would keep the old translation until the next push.
            .id(manager.effectiveLocale.identifier)
    }
}
