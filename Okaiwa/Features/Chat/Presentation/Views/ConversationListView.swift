// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI

/// Conversation list screen — the main chat inbox.
///
/// Displays all conversations sorted by last activity, with pinned
/// conversations at the top. Supports search, folder filtering,
/// swipe actions, and real-time updates.
struct ConversationListView: View {

    @State private var viewModel = ConversationListViewModel()
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch viewModel.loadState {
            case .idle, .loading:
                loadingView

            case .loaded:
                if viewModel.filteredConversations.isEmpty {
                    emptyStateView
                } else {
                    conversationList
                }

            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationTitle("Chats")
        .searchable(
            text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ),
            prompt: "Search conversations"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSheet(.newMessage)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                folderMenu
            }
        }
        .task {
            await viewModel.loadConversations()
            viewModel.startListeningForUpdates()
        }
        .refreshable {
            await viewModel.loadConversations()
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(viewModel.filteredConversations) { conversation in
                ConversationRow(conversation: conversation)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        router.navigate(to: .chat(conversationId: conversation.id))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteConversation(conversation) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            Task { await viewModel.togglePin(for: conversation) }
                        } label: {
                            Label(
                                conversation.isPinned ? "Unpin" : "Pin",
                                systemImage: conversation.isPinned ? "pin.slash" : "pin"
                            )
                        }
                        .tint(OkaiwaTheme.Colors.primaryFallback)
                    }
                    .swipeActions(edge: .leading) {
                        if conversation.unreadCount > 0 {
                            Button {
                                Task { await viewModel.markAsRead(conversation) }
                            } label: {
                                Label("Read", systemImage: "envelope.open")
                            }
                            .tint(OkaiwaTheme.Colors.success)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .withOkaiwaDestinations()
    }

    // MARK: - Folder Menu

    private var folderMenu: some View {
        Menu {
            ForEach(Conversation.Folder.allCases, id: \.self) { folder in
                Button {
                    viewModel.selectedFolder = folder
                } label: {
                    HStack {
                        Text(folder.rawValue.capitalized)
                        if viewModel.selectedFolder == folder {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                if viewModel.selectedFolder != .all {
                    Text(viewModel.selectedFolder.rawValue.capitalized)
                        .font(OkaiwaTheme.Typography.caption)
                }
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading conversations...")
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .padding(.top, OkaiwaTheme.Spacing.sm)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: OkaiwaTheme.Spacing.md) {
            Image(systemName: "message.fill")
                .font(.system(size: 56))
                .foregroundStyle(OkaiwaTheme.Colors.textTertiary)

            Text("No conversations yet")
                .font(OkaiwaTheme.Typography.headline)

            Text("Tap the compose button to start a secure chat.")
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                router.presentSheet(.newMessage)
            } label: {
                Label("New Message", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
            .padding(.top, OkaiwaTheme.Spacing.sm)
        }
        .padding(OkaiwaTheme.Spacing.xl)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: OkaiwaTheme.Spacing.md) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(OkaiwaTheme.Colors.destructive)

            Text(message)
                .font(OkaiwaTheme.Typography.callout)
                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.loadConversations() }
            }
            .buttonStyle(.borderedProminent)
            .tint(OkaiwaTheme.Colors.primaryFallback)
        }
        .padding(OkaiwaTheme.Spacing.xl)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {

    let conversation: Conversation

    private let avatarSize: CGFloat = 52
    private let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: OkaiwaTheme.Spacing.sm) {
            // Avatar
            ZStack {
                Circle()
                    .fill(OkaiwaTheme.Colors.primaryFallback.opacity(0.15))
                    .frame(width: avatarSize, height: avatarSize)

                Text(avatarInitials)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
            }

            // Content
            VStack(alignment: .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                HStack {
                    HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                        if conversation.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
                        }

                        Text(conversation.displayName)
                            .font(OkaiwaTheme.Typography.headline)
                            .lineLimit(1)
                    }

                    Spacer()

                    if let lastMessage = conversation.lastMessage {
                        Text(timeFormatter.localizedString(for: lastMessage.timestamp, relativeTo: Date()))
                            .font(OkaiwaTheme.Typography.caption)
                            .foregroundStyle(
                                conversation.unreadCount > 0
                                    ? OkaiwaTheme.Colors.primaryFallback
                                    : OkaiwaTheme.Colors.textTertiary
                            )
                    }
                }

                HStack {
                    // Message preview
                    if let lastMessage = conversation.lastMessage {
                        HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                            if lastMessage.contentType != .text {
                                Image(systemName: iconForContentType(lastMessage.contentType))
                                    .font(.system(size: 12))
                                    .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
                            }

                            Text(previewText(for: lastMessage))
                                .font(OkaiwaTheme.Typography.subheadline)
                                .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("No messages yet")
                            .font(OkaiwaTheme.Typography.subheadline)
                            .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
                            .italic()
                    }

                    Spacer()

                    // Unread badge
                    if conversation.unreadCount > 0 {
                        Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                conversation.isEffectivelyMuted
                                    ? OkaiwaTheme.Colors.textTertiary
                                    : OkaiwaTheme.Colors.unreadBadge
                            )
                            .clipShape(Capsule())
                    }

                    // Ephemeral indicator
                    if conversation.hasEphemeralTimer {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
                    }
                }
            }
        }
        .padding(.vertical, OkaiwaTheme.Spacing.xxs)
    }

    // MARK: - Helpers

    private var avatarInitials: String {
        let name = conversation.displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func iconForContentType(_ type: Message.ContentType) -> String {
        switch type {
        case .image: return "photo"
        case .video: return "video"
        case .audio, .voiceNote: return "waveform"
        case .file: return "doc"
        case .contact: return "person.crop.circle"
        case .location: return "location"
        case .cryptoPayment: return "bitcoinsign.circle"
        case .systemEvent: return "info.circle"
        case .text: return "text.bubble"
        }
    }

    private func previewText(for message: Conversation.LastMessagePreview) -> String {
        if !message.textPreview.isEmpty {
            return message.textPreview
        }
        switch message.contentType {
        case .image: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
        case .voiceNote: return "Voice message"
        case .file: return "File"
        case .contact: return "Contact"
        case .location: return "Location"
        case .cryptoPayment: return "Crypto payment"
        case .systemEvent: return "System message"
        case .text: return ""
        }
    }
}
