// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import SwiftUI
import PhotosUI

/// Chat view — displays messages in a conversation with input bar.
///
/// Features:
/// - Message bubbles with status indicators
/// - Ephemeral timer indicator
/// - Photo/file attachment picker
/// - Reply-to support
/// - Scroll to bottom on new messages
struct ChatView: View {

    let conversationId: String

    @State private var messages: [Message] = []
    @State private var messageText: String = ""
    @State private var isLoading: Bool = false
    @State private var replyingTo: Message?
    @State private var showAttachmentPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var scrollProxy: ScrollViewProxy?

    @Environment(AppRouter.self) private var router

    // In production: injected from DI
    private let localFingerprint = "local_user_fingerprint"

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messagesScrollView

            // Reply bar
            if let reply = replyingTo {
                replyBar(for: reply)
            }

            // Input bar
            inputBar
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        // Set ephemeral timer
                    } label: {
                        Label("Disappearing Messages", systemImage: "timer")
                    }

                    Button {
                        router.navigate(to: .conversationDetails(conversationId: conversationId))
                    } label: {
                        Label("Conversation Info", systemImage: "info.circle")
                    }

                    Button {
                        router.navigate(to: .verifyIdentity(contactId: conversationId))
                    } label: {
                        Label("Verify Identity", systemImage: "checkmark.shield")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadMessages()
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: OkaiwaTheme.Spacing.xxs) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isMine: message.isMine(localFingerprint: localFingerprint),
                            onReply: {
                                withAnimation(OkaiwaTheme.Animation.fast) {
                                    replyingTo = message
                                }
                            }
                        )
                        .id(message.id)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = "Encrypted content" // Decrypted in prod
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }

                            Button {
                                replyingTo = message
                            } label: {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }

                            if message.isMine(localFingerprint: localFingerprint) {
                                Button(role: .destructive) {
                                    // Delete for everyone
                                } label: {
                                    Label("Delete for Everyone", systemImage: "trash")
                                }
                            }

                            Button(role: .destructive) {
                                // Delete locally
                            } label: {
                                Label("Delete for Me", systemImage: "trash.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, OkaiwaTheme.Spacing.sm)
                .padding(.vertical, OkaiwaTheme.Spacing.xs)
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: OkaiwaTheme.Spacing.xs) {
                // Attachment button
                Button {
                    showAttachmentPicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
                }

                // Text input
                TextField("Message", text: $messageText, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, OkaiwaTheme.Spacing.sm)
                    .padding(.vertical, OkaiwaTheme.Spacing.xs)
                    .background(OkaiwaTheme.Colors.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Send button
                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? OkaiwaTheme.Colors.textTertiary
                                : OkaiwaTheme.Colors.primaryFallback
                        )
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, OkaiwaTheme.Spacing.sm)
            .padding(.vertical, OkaiwaTheme.Spacing.xs)
            .background(OkaiwaTheme.Colors.surface)
        }
        .photosPicker(
            isPresented: $showAttachmentPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        )
    }

    // MARK: - Reply Bar

    private func replyBar(for message: Message) -> some View {
        HStack {
            Rectangle()
                .fill(OkaiwaTheme.Colors.primaryFallback)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to")
                    .font(OkaiwaTheme.Typography.caption2)
                    .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)

                Text("Encrypted message")
                    .font(OkaiwaTheme.Typography.caption)
                    .foregroundStyle(OkaiwaTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(OkaiwaTheme.Animation.fast) {
                    replyingTo = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, OkaiwaTheme.Spacing.md)
        .padding(.vertical, OkaiwaTheme.Spacing.xs)
        .background(OkaiwaTheme.Colors.surfaceSecondary)
    }

    // MARK: - Actions

    private func loadMessages() async {
        isLoading = true
        // In production: load from ChatRepository
        // messages = try await chatRepository.getMessages(conversationId: conversationId, before: nil, limit: 50)
        isLoading = false
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let currentReplyId = replyingTo?.id
        messageText = ""
        replyingTo = nil

        // In production: use SendMessageUseCase
        let message = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            senderFingerprint: localFingerprint,
            encryptedContent: Data(text.utf8),
            contentType: .text,
            timestamp: Date(),
            ephemeralTimer: nil,
            expiresAt: nil,
            status: .sending,
            replyToId: currentReplyId,
            attachments: []
        )

        withAnimation(OkaiwaTheme.Animation.standard) {
            messages.append(message)
        }

        // Scroll to bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                scrollProxy?.scrollTo(message.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {

    let message: Message
    let isMine: Bool
    let onReply: () -> Void

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: OkaiwaTheme.Spacing.xxs) {
                // Message content
                Text("Encrypted message") // Decrypted content in production
                    .font(OkaiwaTheme.Typography.body)
                    .foregroundStyle(OkaiwaTheme.Colors.textPrimary)

                // Metadata row
                HStack(spacing: OkaiwaTheme.Spacing.xxs) {
                    if message.isEphemeral {
                        Image(systemName: "timer")
                            .font(.system(size: 10))
                    }

                    Text(formatTime(message.timestamp))
                        .font(OkaiwaTheme.Typography.caption2)
                        .foregroundStyle(OkaiwaTheme.Colors.textTertiary)

                    if isMine {
                        statusIcon(for: message.status)
                    }
                }
            }
            .padding(.horizontal, OkaiwaTheme.Spacing.sm)
            .padding(.vertical, OkaiwaTheme.Spacing.xs)
            .background(isMine ? OkaiwaTheme.Colors.bubbleOutgoing : OkaiwaTheme.Colors.bubbleIncoming)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func statusIcon(for status: Message.Status) -> some View {
        Group {
            switch status {
            case .sending:
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
            case .sent:
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(OkaiwaTheme.Colors.textTertiary)
            case .delivered:
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
            case .read:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(OkaiwaTheme.Colors.primaryFallback)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(OkaiwaTheme.Colors.destructive)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
