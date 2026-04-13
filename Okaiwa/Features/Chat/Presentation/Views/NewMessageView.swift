import SwiftUI

/// "Nouveau message" — the FAB destination on the Échanges tab.
/// Mirrors `NewMessageScreen.kt`.
///
/// Three utility actions at the top (new group, new channel, invite) +
/// a list of Okaiwa contacts derived from the participants of existing
/// conversations. This screen does NOT request the system contacts
/// permission — the list is purely in-app data. The only path to the
/// device address book (permission-gated) is the "Inviter un contact"
/// action, which pushes ContactPickerView.
public struct NewMessageView: View {
    let onBack: () -> Void
    let onStartConversation: (_ conversationId: String) -> Void
    let onInviteContact: () -> Void
    var onCreateGroup: () -> Void = {}
    var onCreateChannel: () -> Void = {}

    @State private var query: String = ""
    @State private var discoveryModel = DiscoverySearchModel()

    // The mock repo is a singleton for now — the real view will inject
    // a ViewModel that observes `ChatRepository.observeConversations()`.
    @ObservedObject private var repo = MockChatRepository.shared

    public init(
        onBack: @escaping () -> Void,
        onStartConversation: @escaping (String) -> Void,
        onInviteContact: @escaping () -> Void,
        onCreateGroup: @escaping () -> Void = {},
        onCreateChannel: @escaping () -> Void = {}
    ) {
        self.onBack = onBack
        self.onStartConversation = onStartConversation
        self.onInviteContact = onInviteContact
        self.onCreateGroup = onCreateGroup
        self.onCreateChannel = onCreateChannel
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            searchField
            // Live discovery — when the user types a username (3+ chars),
            // the backend's GET /v1/discovery/username/:username is hit
            // after a 300 ms idle window. Match → "Démarrer" pill row.
            // No match → an explicit "Aucun utilisateur" line so the
            // user knows to invite the contact instead.
            DiscoveryResultRow(
                state: discoveryModel.state,
                onStartConversation: { user in
                    onStartConversation(user.accountId)
                }
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    UtilityActionRow(
                        systemIcon: "person.2.badge.plus",
                        title: "Nouveau groupe",
                        trailing: "Jusqu'à 500 membres",
                        isBadge: false,
                        action: onCreateGroup
                    )
                    UtilityActionRow(
                        systemIcon: "megaphone.fill",
                        title: "Nouveau canal",
                        trailing: "Pro",
                        isBadge: true,
                        action: onCreateChannel
                    )
                    UtilityActionRow(
                        systemIcon: "person.crop.circle.badge.plus",
                        title: "Inviter un contact",
                        trailing: nil,
                        isBadge: false,
                        action: onInviteContact
                    )

                    sectionHeader("Trier par heure de connexion")

                    ForEach(filteredContacts, id: \.conversationId) { row in
                        ContactListRow(row: row) {
                            onStartConversation(row.conversationId)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OkaiwaColors.black)
    }

    private var filteredContacts: [OkaiwaRow] {
        let base = repo.conversations.compactMap { conv -> OkaiwaRow? in
            guard let participant = conv.participants.first else { return nil }
            return OkaiwaRow(
                conversationId: conv.id,
                displayName: participant.displayName,
                lastSeenLabel: Self.lastSeenLabel(conv.updatedAt)
            )
        }
        guard !query.isEmpty else { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(OkaiwaColors.white)
                    .padding(12)
            }
            Text("Nouveau message")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OkaiwaColors.white)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OkaiwaColors.muted)
            TextField("", text: $query, prompt: Text("Rechercher des contacts").foregroundStyle(OkaiwaColors.placeholder))
                .foregroundStyle(OkaiwaColors.white)
                .tint(OkaiwaColors.lime)
                .onChange(of: query) { _, newValue in
                    discoveryModel.onQueryChanged(newValue)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(OkaiwaColors.blackElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OkaiwaColors.blackBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(OkaiwaColors.muted)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    /// French last-seen label mirror of `lastSeenLabel` on Android.
    private static func lastSeenLabel(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        let minutes = Int(diff / 60)
        let hours = Int(diff / 3600)
        let days = Int(diff / 86400)
        switch true {
        case minutes < 2:  return "en ligne"
        case minutes < 60: return "en ligne il y a \(minutes) min"
        case hours < 24:   return "en ligne il y a \(hours) h"
        case days < 7:     return "vu il y a \(days) j"
        default:           return "vu récemment"
        }
    }

    private struct OkaiwaRow: Hashable {
        let conversationId: String
        let displayName: String
        let lastSeenLabel: String
        var initial: String {
            displayName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        }
    }

    private struct UtilityActionRow: View {
        let systemIcon: String
        let title: String
        let trailing: String?
        let isBadge: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(OkaiwaColors.lime.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: systemIcon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.lime)
                        )
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OkaiwaColors.white)
                    Spacer()
                    if let trailing {
                        if isBadge {
                            Text(trailing)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.lime)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(OkaiwaColors.lime.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            Text(trailing)
                                .font(.system(size: 12))
                                .foregroundStyle(OkaiwaColors.muted)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private struct ContactListRow: View {
        let row: OkaiwaRow
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(OkaiwaColors.lime.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(row.initial)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(OkaiwaColors.lime)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OkaiwaColors.white)
                        Text(row.lastSeenLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(OkaiwaColors.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DiscoveryResultRow: View {
    let state: DiscoverySearchModel.State
    let onStartConversation: (DiscoveredUser) -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .searching:
            Text("Recherche…")
                .font(.system(size: 12))
                .foregroundStyle(OkaiwaColors.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .notFound:
            Text("Aucun utilisateur Okaiwa pour cet identifiant.")
                .font(.system(size: 13))
                .foregroundStyle(OkaiwaColors.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .error(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(OkaiwaColors.error)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .found(let user):
            Button {
                onStartConversation(user)
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(OkaiwaColors.lime.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(user.username?.first.map { String($0).uppercased() } ?? "@"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OkaiwaColors.lime)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.profile?.displayName ?? user.username ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OkaiwaColors.white)
                        Text("@\(user.username ?? "")")
                            .font(.system(size: 12))
                            .foregroundStyle(OkaiwaColors.muted)
                    }
                    Spacer()
                    Text("Démarrer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OkaiwaColors.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(OkaiwaColors.lime, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
