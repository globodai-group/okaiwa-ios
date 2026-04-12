import Foundation

/// Address-book contact surfaced from the device — mirrors
/// `DeviceContact.kt` on Android.
///
/// `isOnOkaiwa` is populated post-sync by hashing the phone number
/// with PBKDF2 and asking the identity service which hashes it already
/// knows. Until the identity service is wired up the flag is mocked.
public struct DeviceContact: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let phoneNumberE164: String
    public let avatarData: Data?
    public let isOnOkaiwa: Bool
    public let okaiwaUsername: String?

    public init(
        id: String,
        displayName: String,
        phoneNumberE164: String,
        avatarData: Data? = nil,
        isOnOkaiwa: Bool = false,
        okaiwaUsername: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.phoneNumberE164 = phoneNumberE164
        self.avatarData = avatarData
        self.isOnOkaiwa = isOnOkaiwa
        self.okaiwaUsername = okaiwaUsername
    }

    /// First-letter initial used in the placeholder avatar medallion.
    public var initial: String {
        displayName.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}
