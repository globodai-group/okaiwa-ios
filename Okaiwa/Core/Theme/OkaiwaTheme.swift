// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

/// Design system for Okaiwa.
///
/// Centralized colors, typography, spacing, and component styles
/// that adapt to light and dark mode.
enum OkaiwaTheme {

    // MARK: - Colors

    enum Colors {
        /// Primary brand color — deep teal
        static let primary = Color("OkaiwaPrimary", bundle: .main)
            .opacity(1) // Fallback handled below

        /// Accent for interactive elements
        static let accent = Color("OkaiwaAccent", bundle: .main)
            .opacity(1)

        /// Destructive actions (delete, block, errors)
        static let destructive = Color.red

        /// Success states (verified, sent)
        static let success = Color.green

        /// Warning states
        static let warning = Color.orange

        /// Surface background (cards, sheets)
        static let surface = Color(.systemBackground)

        /// Secondary background (grouped table sections)
        static let surfaceSecondary = Color(.secondarySystemBackground)

        /// Tertiary background
        static let surfaceTertiary = Color(.tertiarySystemBackground)

        /// Primary text
        static let textPrimary = Color(.label)

        /// Secondary text
        static let textSecondary = Color(.secondaryLabel)

        /// Tertiary text
        static let textTertiary = Color(.tertiaryLabel)

        /// Chat bubble — outgoing
        static let bubbleOutgoing = Color.teal.opacity(0.15)

        /// Chat bubble — incoming
        static let bubbleIncoming = Color(.systemGray5)

        /// Unread badge
        static let unreadBadge = Color.teal

        // MARK: Hardcoded Fallbacks

        /// Use these when asset catalog colors are not configured yet.
        static let primaryFallback = Color(red: 0.0, green: 0.59, blue: 0.53) // #009688
        static let accentFallback = Color(red: 0.0, green: 0.74, blue: 0.83)  // #00BCD4
    }

    // MARK: - Typography

    enum Typography {
        /// Large title — screen headers
        static let largeTitle = Font.largeTitle.weight(.bold)

        /// Title — section headers
        static let title = Font.title2.weight(.semibold)

        /// Headline — cell titles, prominent labels
        static let headline = Font.headline.weight(.semibold)

        /// Subheadline — secondary cell text
        static let subheadline = Font.subheadline

        /// Body — main content text
        static let body = Font.body

        /// Callout — descriptions, hints
        static let callout = Font.callout

        /// Caption — timestamps, metadata
        static let caption = Font.caption

        /// Caption 2 — small labels
        static let caption2 = Font.caption2

        /// Monospaced — addresses, fingerprints, hashes
        static let mono = Font.system(.body, design: .monospaced)

        /// Monospaced small — compact addresses
        static let monoSmall = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        /// 4pt
        static let xxs: CGFloat = 4
        /// 8pt
        static let xs: CGFloat = 8
        /// 12pt
        static let sm: CGFloat = 12
        /// 16pt
        static let md: CGFloat = 16
        /// 20pt
        static let lg: CGFloat = 20
        /// 24pt
        static let xl: CGFloat = 24
        /// 32pt
        static let xxl: CGFloat = 32
        /// 48pt
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        /// 8pt — small components (badges)
        static let small: CGFloat = 8
        /// 12pt — medium components (cards)
        static let medium: CGFloat = 12
        /// 16pt — large components (sheets)
        static let large: CGFloat = 16
        /// 24pt — extra large (floating buttons)
        static let extraLarge: CGFloat = 24
        /// Full circle
        static let circle: CGFloat = .infinity
    }

    // MARK: - Shadows

    enum Shadows {
        static let small = ShadowStyle(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        static let medium = ShadowStyle(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        static let large = ShadowStyle(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    // MARK: - Animation

    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let spring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Modifiers

extension View {

    func okaiwaShadow(_ style: ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func okaiwaCard() -> some View {
        self
            .background(OkaiwaTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: OkaiwaTheme.CornerRadius.medium))
            .okaiwaShadow(OkaiwaTheme.Shadows.small)
    }
}
