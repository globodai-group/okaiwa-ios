import SwiftUI

/// Primary surfaces of the app — mirrors `MainTab` on Android.
///
/// The declared order drives the TabView tab order, matching the Android
/// bottom navigation so users moving between platforms see identical
/// placement.
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

/// Bottom-bar host mirror of `MainScaffold.kt`.
///
/// Uses `TabView` so each tab's state persists across switches (matching
/// the Android behaviour where tab surfaces live inside the same Scaffold
/// rather than being pushed/popped on a NavHost).
public struct MainScaffold<Content: View>: View {
    @State private var selected: MainTab = .chats
    let content: (MainTab) -> Content

    public init(@ViewBuilder content: @escaping (MainTab) -> Content) {
        self.content = content
    }

    public var body: some View {
        TabView(selection: $selected) {
            ForEach(MainTab.allCases) { tab in
                content(tab)
                    .tabItem {
                        Label(tab.label, systemImage: selected == tab ? tab.systemIcon : tab.systemIconUnselected)
                    }
                    .tag(tab)
            }
        }
        .tint(OkaiwaColors.lime)
        .onAppear {
            // Match the Android bar: black background, lime selected
            // label, muted gray unselected label. UIKit appearance APIs
            // are the only way to style `TabView` before SwiftUI exposes
            // a native tab appearance modifier.
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(OkaiwaColors.black)
            appearance.shadowColor = UIColor(OkaiwaColors.blackBorder)

            for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                item.normal.iconColor = UIColor(OkaiwaColors.muted)
                item.normal.titleTextAttributes = [.foregroundColor: UIColor(OkaiwaColors.muted)]
                item.selected.iconColor = UIColor(OkaiwaColors.lime)
                item.selected.titleTextAttributes = [.foregroundColor: UIColor(OkaiwaColors.lime)]
            }

            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
