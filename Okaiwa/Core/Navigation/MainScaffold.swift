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

    var label: String {
        switch self {
        case .chats: return "Échanges"
        case .wallet: return "Wallet"
        case .settings: return "Paramètres"
        case .profile: return "Profil"
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
            // `.ultraThinMaterial` gives the system's adaptive blur;
            // we tint it with the elevated canvas at 78 % so the brand
            // keeps its dark-first identity instead of the gray system
            // glass. Rounded to 16 pt to match the Welcome CTAs.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(OkaiwaColors.blackElevated.opacity(0.78))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(OkaiwaColors.blackBorder.opacity(0.6), lineWidth: 1)
        )
    }
}

private struct TabItem: View {
    let tab: MainTab
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.systemIcon : tab.systemIconUnselected)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                Text(tab.label)
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
