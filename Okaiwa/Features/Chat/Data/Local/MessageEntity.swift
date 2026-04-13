// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import GRDB

/// GRDB record for a single message row — iOS twin of
/// `MessageEntity.kt`.
///
/// Plaintext `body` is stored here intentionally — the encryption
/// layer is Signal Protocol on the wire; once decrypted on-device the
/// UX needs to render the original text on every scroll, which means
/// caching. The row itself is protected at rest by SQLCipher
/// (AES-256 on every page).
///
/// Delivery state machine mirrors the Android constants.
struct MessageEntity: Codable, FetchableRecord, PersistableRecord, Hashable, Equatable, Sendable {
    static let databaseTableName = "messages"

    /// Relay messageId on inbound, a client-minted UUID on outbound.
    var id: String
    var conversationId: String
    /// Device id of the sender — our own deviceId on outbound, peer's on inbound.
    var senderDeviceId: String
    var body: String
    var timestamp: Int64
    var isOutbound: Bool
    var deliveryState: String

    init(
        id: String,
        conversationId: String,
        senderDeviceId: String,
        body: String,
        timestamp: Int64,
        isOutbound: Bool,
        deliveryState: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderDeviceId = senderDeviceId
        self.body = body
        self.timestamp = timestamp
        self.isOutbound = isOutbound
        self.deliveryState = deliveryState
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let conversationId = Column(CodingKeys.conversationId)
        static let senderDeviceId = Column(CodingKeys.senderDeviceId)
        static let timestamp = Column(CodingKeys.timestamp)
        static let deliveryState = Column(CodingKeys.deliveryState)
        static let isOutbound = Column(CodingKeys.isOutbound)
    }
}

/// Mirror of `object DeliveryState` on Android. Kept as raw strings
/// (not an enum) so the DB schema is byte-identical between platforms
/// — a restore from an Android backup flows without a migration step.
enum DeliveryState {
    static let pending = "PENDING"
    static let sent = "SENT"
    static let delivered = "DELIVERED"
    static let failed = "FAILED"
}
