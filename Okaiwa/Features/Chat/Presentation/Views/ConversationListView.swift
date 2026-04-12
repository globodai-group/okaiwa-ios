import SwiftUI

/// Conversation list — mirrors `ConversationListScreen.kt`.
///
/// Top bar shows "Okaiwa" wordmark + search + contacts action on the
/// right. A lime new-conversation FAB floats above the tab bar, offset
/// via `@Environment(\.floatingBarInset)`.
///
/// The rich list rendering (pinned conversations, swipe actions, search
/// filter, real-time updates) will be restored once the ViewModel is
/// wired up to the real ChatRepository — for now the empty state is the
/// only visible surface because every call to `StubChatRepository`
/// returns an empty list.
public struct ConversationListView: View {
    let onNavigateToChat: (String) -> Void
    let onNavigateToContacts: () -> Void

    @Environment(\.floatingBarInset) private var floatingBarInset: CGFloat

    public init(
        onNavigateToChat: @escaping (String) -> Void,
        onNavigateToContacts: @escaping () -> Void
    ) {
        self.onNavigateToChat = onNavigateToChat
        self.onNavigateToContacts = onNavigateToContacts
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                TopBar(
                    onSearchTap: { /* TODO: inline search */ },
                    onContactsTap: onNavigateToContacts
                )

                EmptyConversationsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, floatingBarInset)
            }

            // New-conversation FAB — rounded square lime tile. The
            // 16 pt corner radius matches every other rounded surface in
            // the app (Welcome CTAs, the floating nav bar itself). A
            // chat bubble reads more directly than the earlier pencil
            // icon for "new conversation".
            Button(action: onNavigateToContacts) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(OkaiwaColors.black)
                    .frame(width: 56, height: 56)
                    .background(OkaiwaColors.lime)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 3)
            }
            .padding(.trailing, 20)
            // 16 pt gutter above the floating bar keeps the FAB
            // comfortably off the bar rather than hugging it.
            .padding(.bottom, floatingBarInset + 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }
}

private struct TopBar: View {
    let onSearchTap: () -> Void
    let onContactsTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("Okaiwa")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
                .padding(.leading, 24)

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }

            Button(action: onContactsTap) {
                Image(systemName: "person.2")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyConversationsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(OkaiwaColors.muted)

            Text("Aucune conversation")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)

            Text("Commencez une conversation chiffrée avec un contact.")
                .font(.system(size: 14))
                .foregroundStyle(OkaiwaColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
