import Foundation
import os

/// Persistent home for the identity service session — mirrors the
/// Android `SessionStore.kt`.
///
/// Tokens land in the iOS Keychain with `kSecAttrAccessibleWhenUnlocked-
/// ThisDeviceOnly` (set inside `KeychainManager`), so they are:
/// - readable only after device unlock,
/// - excluded from iCloud + local backups,
/// - not migrated to a new device on restore.
///
/// Persistence policy by field:
///   - everything except phoneHash → ONE JSON blob in the Keychain
///   - phoneHash → IN-MEMORY ONLY, never written to Keychain
///
/// Why one blob rather than seven keys: the previous multi-write
/// pattern was non-atomic. A process kill or Keychain failure
/// mid-`save()` could leave a half-written record where accessToken
/// was set but deviceToken was not, which made the splash gate route
/// to Welcome while the stale tokens remained on disk indefinitely
/// (security review on okaiwa-android@386d11d, P0 confidence 8/10).
/// A single Keychain item inherits SecItemAdd / SecItemUpdate's
/// all-or-nothing semantics.
///
/// The phone hash is excluded from disk by design: it lets an
/// attacker with Keychain read access (jailbroken device, another app
/// in the same access group if misconfigured) confirm the device
/// owner's phone number by hashing every candidate E.164 number and
/// comparing.
///
/// The in-memory `@Observable` snapshot mirrors the Keychain so
/// SwiftUI views can observe sign-in / sign-out without polling.
@Observable
@MainActor
final class SessionStore {
    struct Session: Equatable, Sendable {
        let accountId: String
        let phoneHash: String
        let accessToken: String
        let refreshToken: String
        let expiresAtEpochSeconds: Int64
        var deviceId: String = ""
        var deviceToken: String = ""
        /// Whether the post-verify profile setup (username, displayName,
        /// …) has been completed. Used by the navigation layer to
        /// decide between ProfileSetup and Main on cold start.
        var profileSetupDone: Bool = false

        var isFresh: Bool {
            Int64(Date().timeIntervalSince1970) < expiresAtEpochSeconds
        }

        var isVerified: Bool {
            !accessToken.isEmpty && !deviceToken.isEmpty
        }
    }

    private(set) var current: Session?

    private let keychain: KeychainManager
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SessionStore")

    private enum Key {
        static let blob = "identity.session.v1"
    }

    /// Bumped when [PersistedSession] gains/loses a field in an
    /// incompatible way. Older blobs are wiped on load instead of
    /// produce subtle hydrated-with-defaults bugs.
    private static let schemaVersion: Int = 1

    init(keychain: KeychainManager = KeychainManager()) {
        self.keychain = keychain
        self.current = Self.loadFromDisk(keychain)
    }

    // MARK: - Mutations

    func save(_ session: Session) {
        let persisted = PersistedSession(
            schemaVersion: Self.schemaVersion,
            accountId: session.accountId,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAtEpochSeconds: session.expiresAtEpochSeconds,
            deviceId: session.deviceId,
            deviceToken: session.deviceToken,
            profileSetupDone: session.profileSetupDone
        )
        do {
            let data = try JSONEncoder().encode(persisted)
            try keychain.save(data: data, forKey: Key.blob)
            current = session
            // accountId is a stable cross-session identifier; logging
            // it as `.public` would persist it into Sysdiagnose archives
            // and let support tooling correlate users across sessions.
            // `.private` keeps it out of unified logs unless the user
            // explicitly opts in via a profile.
            logger.info("Session saved — account \(session.accountId.prefix(8), privacy: .private)")
        } catch {
            // Persistence failed — DO NOT update the in-memory snapshot.
            // The user's next API call surfaces a session-expired path
            // naturally; better that than a half-saved state where the
            // UI thinks the user is signed in but tokens won't survive
            // the next launch.
            logger.error("Session persist failure — keeping prior in-memory state")
        }
    }

    /// Shorthand to mark the user's profile setup as complete without
    /// having to reconstruct the full session struct at every call site.
    func markProfileSetupDone() {
        guard var session = current else { return }
        session.profileSetupDone = true
        save(session)
    }

    func clear() {
        try? keychain.delete(forKey: Key.blob)
        current = nil
        logger.info("Session cleared")
    }

    // MARK: - Private

    private static func loadFromDisk(_ keychain: KeychainManager) -> Session? {
        guard
            let dataOpt = try? keychain.load(forKey: Key.blob),
            let data = dataOpt
        else { return nil }

        guard let persisted = try? JSONDecoder().decode(PersistedSession.self, from: data),
              persisted.schemaVersion == schemaVersion
        else {
            // Schema mismatch or corrupted blob — wipe and force a
            // clean slate. Better to make the user re-authenticate
            // than to ship them into a half-hydrated state where some
            // fields default to "" and produce subtle bugs.
            try? keychain.delete(forKey: Key.blob)
            return nil
        }

        // phoneHash is intentionally not restored — see the class kdoc.
        return Session(
            accountId: persisted.accountId,
            phoneHash: "",
            accessToken: persisted.accessToken,
            refreshToken: persisted.refreshToken,
            expiresAtEpochSeconds: persisted.expiresAtEpochSeconds,
            deviceId: persisted.deviceId,
            deviceToken: persisted.deviceToken,
            profileSetupDone: persisted.profileSetupDone
        )
    }
}

/// Wire-format struct persisted in the Keychain. Kept separate from
/// the in-memory `Session` so we can include a schema version tag and
/// explicitly EXCLUDE phoneHash from disk.
private struct PersistedSession: Codable {
    let schemaVersion: Int
    let accountId: String
    let accessToken: String
    let refreshToken: String
    let expiresAtEpochSeconds: Int64
    let deviceId: String
    let deviceToken: String
    let profileSetupDone: Bool
}
