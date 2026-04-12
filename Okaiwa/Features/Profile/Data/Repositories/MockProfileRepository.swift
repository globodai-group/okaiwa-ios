import Foundation
import Combine

/// In-memory mock — mirrors `MockProfileRepository.kt`. Surfaces a
/// believable identity card so the Profil tab can be reviewed before
/// the identity service is wired in.
public final class MockProfileRepository: ObservableObject {
    public static let shared = MockProfileRepository()

    @Published public private(set) var profile: UserProfile? = UserProfile(
        userId: "me",
        displayName: "Kevin",
        username: "@asmista",
        phoneNumberE164: "+971 56 486 1094",
        bio: "Builder · Globodai FZCO",
        avatarUrl: nil,
        isVerified: true,
        isOnline: true
    )

    public func setDisplayName(_ newName: String) {
        guard var p = profile else { return }
        p = UserProfile(
            userId: p.userId, displayName: newName, username: p.username,
            phoneNumberE164: p.phoneNumberE164, bio: p.bio, avatarUrl: p.avatarUrl,
            isVerified: p.isVerified, isOnline: p.isOnline, lastSeenAt: p.lastSeenAt
        )
        profile = p
    }

    public func setBio(_ newBio: String) {
        guard var p = profile else { return }
        p = UserProfile(
            userId: p.userId, displayName: p.displayName, username: p.username,
            phoneNumberE164: p.phoneNumberE164,
            bio: newBio.isEmpty ? nil : newBio,
            avatarUrl: p.avatarUrl, isVerified: p.isVerified,
            isOnline: p.isOnline, lastSeenAt: p.lastSeenAt
        )
        profile = p
    }

    public func setUsername(_ newUsername: String) {
        guard var p = profile else { return }
        let normalized = newUsername.hasPrefix("@") ? newUsername : "@\(newUsername)"
        p = UserProfile(
            userId: p.userId, displayName: p.displayName, username: normalized,
            phoneNumberE164: p.phoneNumberE164, bio: p.bio, avatarUrl: p.avatarUrl,
            isVerified: p.isVerified, isOnline: p.isOnline, lastSeenAt: p.lastSeenAt
        )
        profile = p
    }
}
