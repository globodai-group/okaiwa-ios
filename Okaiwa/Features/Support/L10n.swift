// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import SwiftUI

/// Lightweight shim so every call site in `OkaiwaFeatures` resolves
/// localized strings against the module's resource bundle without
/// repeating `bundle: .module` at every call. Keeps the code readable
/// and prevents stray `NSLocalizedString` fallbacks that would search
/// `Bundle.main` and silently return the key as the value.
///
/// Usage patterns:
///   - Static SwiftUI text: `Text(L10n.key("welcome_tagline"))`
///     (returns a `LocalizedStringKey` keyed against Features' bundle).
///   - Formatted / interpolated text: `L10n.string("otp_subtitle_format", phone)`
///     (returns a plain `String` after formatting, useful when we need
///     to feed the value into `Alert`, `String`-only parameters, or
///     non-SwiftUI callers like `UIActivityViewController`).
///
/// The two entry points cover every translation pattern we currently
/// have. If a future use case needs attributed strings or pluralization,
/// extend here — don't drop to `NSLocalizedString` in feature code.
public enum L10n {
    /// Returns a `LocalizedStringKey` bound to the Features bundle.
    /// SwiftUI will perform the lookup at render time, so the string
    /// automatically tracks the runtime `\.locale` environment value.
    public static func key(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }

    /// Resolves `key` to a plain `String` using the current locale
    /// environment of the Features bundle. Applies the format arguments
    /// via `String(format:locale:arguments:)` so placeholders like
    /// `%d`, `%@`, `%.2f` behave correctly in every supported locale.
    ///
    /// Prefer `L10n.key(_:)` inside SwiftUI views — this overload is
    /// only for code paths that hand off to APIs expecting a `String`.
    public static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(
            key,
            tableName: nil,
            bundle: .module,
            value: key,
            comment: ""
        )
        if args.isEmpty { return format }
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
