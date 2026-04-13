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
///   - accountId, accessToken, refreshToken, expiresAt → Keychain
///   - phoneHash → IN-MEMORY ONLY, never written to Keychain
///
/// The phone hash is excluded from disk by design: it lets an attacker
/// with Keychain read access (jailbroken device, another app in the
/// same access group if misconfigured) confirm the device owner's
/// phone number by hashing every candidate E.164 number and comparing.
/// Keeping it in RAM means a clean app launch starts with an empty
/// phoneHash, and the user is asked to enter their number again
/// before /v1/auth/verify can be called.
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
        static let accessToken = "identity.session.access_token"
        static let refreshToken = "identity.session.refresh_token"
        static let accountId = "identity.session.account_id"
        static let expiresAt = "identity.session.expires_at"
        static let deviceId = "identity.session.device_id"
        static let deviceToken = "identity.session.device_token"
        static let profileSetupDone = "identity.session.profile_setup_done"
    }

    init(keychain: KeychainManager = KeychainManager()) {
        self.keychain = keychain
        self.current = Self.loadFromDisk(keychain)
    }

    // MARK: - Mutations

    func save(_ session: Session) {
        do {
            try keychain.saveString(session.accountId, forKey: Key.accountId)
            try keychain.saveString(session.accessToken, forKey: Key.accessToken)
            try keychain.saveString(session.refreshToken, forKey: Key.refreshToken)
            try keychain.saveString(String(session.expiresAtEpochSeconds), forKey: Key.expiresAt)
            try keychain.saveString(session.deviceId, forKey: Key.deviceId)
            try keychain.saveString(session.deviceToken, forKey: Key.deviceToken)
            try keychain.saveString(session.profileSetupDone ? "1" : "0", forKey: Key.profileSetupDone)
            current = session
            logger.info("Session saved — account \(session.accountId.prefix(8), privacy: .public)")
        } catch {
            logger.error("Session persist failure: \(error.localizedDescription)")
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
        for key in [Key.accessToken, Key.refreshToken, Key.accountId, Key.expiresAt, Key.deviceId, Key.deviceToken, Key.profileSetupDone] {
            try? keychain.delete(forKey: key)
        }
        current = nil
        logger.info("Session cleared")
    }

    // MARK: - Private

    private static func loadFromDisk(_ keychain: KeychainManager) -> Session? {
        guard
            let accountId = try? keychain.loadString(forKey: Key.accountId),
            let accessToken = try? keychain.loadString(forKey: Key.accessToken),
            let refreshToken = try? keychain.loadString(forKey: Key.refreshToken),
            let expiresRaw = try? keychain.loadString(forKey: Key.expiresAt),
            let accountIdValue = accountId,
            let accessTokenValue = accessToken,
            let refreshTokenValue = refreshToken,
            let expiresValue = expiresRaw,
            let expiresAt = Int64(expiresValue)
        else { return nil }

        let deviceId = ((try? keychain.loadString(forKey: Key.deviceId)) ?? nil) ?? ""
        let deviceToken = ((try? keychain.loadString(forKey: Key.deviceToken)) ?? nil) ?? ""
        let profileDoneRaw = ((try? keychain.loadString(forKey: Key.profileSetupDone)) ?? nil) ?? "0"

        // phoneHash is intentionally not restored — see the class kdoc.
        // The session is hydrated without it; the verify step will fail
        // until the user re-enters the phone, which calls register()
        // again and refreshes the in-memory hash.
        return Session(
            accountId: accountIdValue,
            phoneHash: "",
            accessToken: accessTokenValue,
            refreshToken: refreshTokenValue,
            expiresAtEpochSeconds: expiresAt,
            deviceId: deviceId,
            deviceToken: deviceToken,
            profileSetupDone: profileDoneRaw == "1"
        )
    }
}
