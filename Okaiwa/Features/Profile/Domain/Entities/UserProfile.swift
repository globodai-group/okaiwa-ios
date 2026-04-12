import Foundation

/// Public profile of the current user — surfaced in the Profil tab.
/// Mirrors `UserProfile.kt` field for field.
///
/// Backend endpoints documented on Android stay authoritative — see
/// `okaiwa-android/.../UserProfile.kt`.
public struct UserProfile: Identifiable, Equatable, Sendable {
    public let userId: String
    public let displayName: String
    public let username: String
    public let phoneNumberE164: String
    public let bio: String?
    public let avatarUrl: String?
    public let isVerified: Bool
    public let isOnline: Bool
    public let lastSeenAt: Date?

    public var id: String { userId }

    public init(
        userId: String,
        displayName: String,
        username: String,
        phoneNumberE164: String,
        bio: String? = nil,
        avatarUrl: String? = nil,
        isVerified: Bool = false,
        isOnline: Bool = true,
        lastSeenAt: Date? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.username = username
        self.phoneNumberE164 = phoneNumberE164
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.isVerified = isVerified
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
    }
}
