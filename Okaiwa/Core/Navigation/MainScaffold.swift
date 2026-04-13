import SwiftUI

/// Primary surfaces of the app — mirrors `MainTab` on Android.
///
/// The declared order drives the floating bar tab order, matching the
/// Android bottom navigation so users moving between platforms see
/// identical placement.
public enum MainTab: Int, CaseIterable, Identifiable {
    case chats
    case wallet
    case settings
    case profile

    public var id: Int { rawValue }

    /// Localized label key for this tab. Returning a resource key (not
    /// a resolved string) lets the SwiftUI `Text(LocalizedStringKey)`
    /// overload pick up the tab title from the consumer's bundle —
    /// `MainTab` lives in OkaiwaCore but the label strings live in
    /// OkaiwaFeatures' resource table, so exposing the key and letting
    /// the consumer do the lookup avoids a cross-module bundle hop.
    var labelKey: String {
        switch self {
        case .chats: return "tab_chats"
        case .wallet: return "tab_wallet"
        case .settings: return "tab_settings"
        case .profile: return "tab_profile"
        }
    }

    var systemIcon: String {
        switch self {
        case .chats: return "bubble.left.fill"
        case .wallet: return "wallet.pass.fill"
        case .settings: return "gearshape.fill"
        case .profile: return "person.fill"
        }
    }

    var systemIconUnselected: String {
        switch self {
        case .chats: return "bubble.left"
        case .wallet: return "wallet.pass"
        case .settings: return "gearshape"
        case .profile: return "person"
        }
    }
}

/// Inset the floating bar reserves at the bottom of scrollable tab
/// content so the last row doesn't hide behind the translucent bar.
/// Mirrors the `LocalFloatingBarPadding` CompositionLocal on Android.
public struct FloatingBarInsetKey: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
    var floatingBarInset: CGFloat {
        get { self[FloatingBarInsetKey.self] }
        set { self[FloatingBarInsetKey.self] = newValue }
    }
}

/// Bottom-bar host that mirrors `MainScaffold.kt`.
///
/// The bar floats over the tab content — the content scrolls through
/// the translucent layer rather than being pushed up. Corner radius
/// matches the 16-pt button radius on the Welcome CTAs, not a Telegram
/// pill shape.
public struct MainScaffold<Content: View>: View {
    @State private var selected: MainTab = .chats
    let content: (MainTab) -> Content

    private let barHeight: CGFloat = 64
    private let barBottomMargin: CGFloat = 12
    private let barHorizontalMargin: CGFloat = 16

    public init(@ViewBuilder content: @escaping (MainTab) -> Content) {
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            OkaiwaColors.black.ignoresSafeArea()

            content(selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.floatingBarInset, barHeight + barBottomMargin + 16)

            FloatingNavBar(selected: $selected)
                .frame(height: barHeight)
                .padding(.horizontal, barHorizontalMargin)
                .padding(.bottom, barBottomMargin)
        }
    }
}

private struct FloatingNavBar: View {
    @Binding var selected: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                TabItem(tab: tab, isSelected: selected == tab) {
                    selected = tab
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(
            // `.ultraThinMaterial` provides the system's adaptive blur;
            // we tint it with the elevated canvas at 92 % so the brand
            // keeps its dark-first identity and tab labels never sit on
            // noisy artwork (the 78 % version read as too washed-out).
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(OkaiwaColors.blackElevated.opacity(0.92))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(OkaiwaColors.blackBorder.opacity(0.7), lineWidth: 1)
        )
        // Soft lift — reads as "floating" without a harsh halo.
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
    }
}

private struct TabItem: View {
    let tab: MainTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        // `.plain` button style already drops the system highlight — no
        // ripple equivalent to disable, unlike Compose's selectable.
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.systemIcon : tab.systemIconUnselected)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                // `LocalizedStringKey` resolves against the module
                // that created the Text — MainScaffold lives in Core,
                // so the `tab_*` keys are declared in Core's own
                // `Localizable.strings` tables.
                Text(LocalizedStringKey(tab.labelKey), bundle: .module)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? OkaiwaColors.lime : OkaiwaColors.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
