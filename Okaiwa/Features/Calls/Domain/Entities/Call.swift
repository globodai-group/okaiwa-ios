// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// An encrypted voice or video call.
///
/// All calls in Okaiwa are end-to-end encrypted using SRTP with
/// keys derived from the Signal Protocol session. The server acts
/// only as a TURN relay and never has access to call media.
struct Call: Identifiable, Codable, Sendable, Equatable {

    /// Unique call identifier (UUID v4).
    let id: String

    /// Participants in the call (fingerprints).
    let participants: [CallParticipant]

    /// Call type.
    let type: CallType

    /// Call direction (relative to the local user).
    let direction: Direction

    /// Current call status.
    var status: Status

    /// Call duration in seconds (nil if not yet connected).
    var duration: TimeInterval?

    /// When the call was initiated.
    let initiatedAt: Date

    /// When the call was answered (nil if missed/rejected).
    var answeredAt: Date?

    /// When the call ended.
    var endedAt: Date?

    /// Whether the call media is encrypted (always true in Okaiwa).
    let encrypted: Bool = true

    /// TURN server used for relay.
    var relayServer: String?

    /// Associated conversation ID.
    let conversationId: String?

    // MARK: - Nested Types

    enum CallType: String, Codable, Sendable {
        case voice
        case video
    }

    enum Direction: String, Codable, Sendable {
        case incoming
        case outgoing
    }

    enum Status: String, Codable, Sendable {
        /// Call is being set up (signaling).
        case ringing
        /// Call is connected and active.
        case active
        /// Call ended normally.
        case ended
        /// Call was missed (incoming, not answered).
        case missed
        /// Call was rejected by the recipient.
        case rejected
        /// Call failed due to network or crypto error.
        case failed
        /// Call was declined (incoming, user declined).
        case declined
        /// Call is on hold.
        case onHold
    }

    /// A participant in the call.
    struct CallParticipant: Codable, Sendable, Equatable {
        let fingerprint: String
        let username: String
        var isMuted: Bool
        var isVideoEnabled: Bool
        var joinedAt: Date?
    }
}

// MARK: - Convenience

extension Call {

    /// Human-readable call duration (e.g., "2:45").
    var durationDisplay: String? {
        guard let duration, duration > 0 else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Whether the call was missed or rejected (for call history display).
    var isMissed: Bool {
        status == .missed || status == .rejected || status == .declined
    }

    /// The other participant in a 1:1 call.
    var otherParticipant: CallParticipant? {
        participants.first // In production: filter out local user
    }

    /// Display name for the call entry.
    var displayName: String {
        if participants.count == 1 {
            return participants[0].username
        }
        return participants.map(\.username).joined(separator: ", ")
    }

    /// SF Symbol for the call type and direction.
    var iconName: String {
        switch (type, direction, status) {
        case (.video, _, _):
            return "video.fill"
        case (.voice, .outgoing, _):
            return "phone.arrow.up.right.fill"
        case (.voice, .incoming, .missed):
            return "phone.arrow.down.left.fill"
        case (.voice, .incoming, .declined):
            return "phone.down.fill"
        case (.voice, .incoming, _):
            return "phone.arrow.down.left.fill"
        }
    }

    /// Color for the call status indicator.
    var statusTint: String {
        switch status {
        case .missed, .rejected, .failed, .declined:
            return "red"
        case .active, .ended:
            return "green"
        case .ringing, .onHold:
            return "orange"
        }
    }
}
