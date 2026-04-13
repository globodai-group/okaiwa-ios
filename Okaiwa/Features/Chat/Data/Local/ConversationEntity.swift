// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB

/// GRDB record for a 1:1 conversation row — iOS twin of
/// `ConversationEntity.kt` (Android Room entity).
///
/// The peer's cryptographic identity (accountId / deviceId /
/// registrationId / identityKey base64) is duplicated here so the chat
/// layer can build a libsignal `ProtocolAddress` without a second
/// round-trip to discovery when the user taps an existing thread.
///
/// All writes go through SQLCipher — see `OkaiwaDatabase`.
struct ConversationEntity: Codable, FetchableRecord, PersistableRecord, Hashable, Equatable, Sendable {
    static let databaseTableName = "conversations"

    var id: String
    var peerAccountId: String
    var peerUsername: String?
    var peerDisplayName: String?
    var peerDeviceId: String
    var peerRegistrationId: Int
    /// Base64-encoded Curve25519 identity public key of the peer.
    /// Empty on first inbound contact until the polling service
    /// extracts it from a PreKeySignalMessage header — subsequent
    /// TOFU checks then compare against this pinned value.
    var peerIdentityKey: String
    var lastMessageId: String?
    var lastMessagePreview: String?
    var lastMessageAt: Int64
    var unreadCount: Int
    var createdAt: Int64
    var updatedAt: Int64

    init(
        id: String,
        peerAccountId: String,
        peerUsername: String? = nil,
        peerDisplayName: String? = nil,
        peerDeviceId: String,
        peerRegistrationId: Int,
        peerIdentityKey: String,
        lastMessageId: String? = nil,
        lastMessagePreview: String? = nil,
        lastMessageAt: Int64 = 0,
        unreadCount: Int = 0,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.peerAccountId = peerAccountId
        self.peerUsername = peerUsername
        self.peerDisplayName = peerDisplayName
        self.peerDeviceId = peerDeviceId
        self.peerRegistrationId = peerRegistrationId
        self.peerIdentityKey = peerIdentityKey
        self.lastMessageId = lastMessageId
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Column names — used by the DAO layer for UPDATE clauses without
    /// string-typos. GRDB exposes a `CodingKeys` column-name mapping
    /// out of the box via `Codable`, but the explicit enum keeps the
    /// DAO code self-documenting.
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let peerAccountId = Column(CodingKeys.peerAccountId)
        static let peerDeviceId = Column(CodingKeys.peerDeviceId)
        static let peerIdentityKey = Column(CodingKeys.peerIdentityKey)
        static let peerRegistrationId = Column(CodingKeys.peerRegistrationId)
        static let peerUsername = Column(CodingKeys.peerUsername)
        static let lastMessageId = Column(CodingKeys.lastMessageId)
        static let lastMessagePreview = Column(CodingKeys.lastMessagePreview)
        static let lastMessageAt = Column(CodingKeys.lastMessageAt)
        static let unreadCount = Column(CodingKeys.unreadCount)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
