import Contacts
import Foundation

/// `CNContactStore`-backed implementation of [DeviceContactsRepository].
/// Mirrors `AndroidDeviceContactsRepository.kt` — same mock "on Okaiwa"
/// coin-flip so the UI split (message vs invite) can be reviewed
/// end-to-end before the identity-service lookup is wired in.
public final class IOSDeviceContactsRepository: DeviceContactsRepository {
    private let store = CNContactStore()

    public init() {}

    public func loadContacts() async -> [DeviceContact] {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return []
        }

        let keys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneNumbersKey,
            CNContactImageDataKey,
        ] as [CNKeyDescriptor]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault

        var results: [DeviceContact] = []
        var seen = Set<String>()

        do {
            try store.enumerateContacts(with: request) { contact, _ in
                let display = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard let rawPhone = contact.phoneNumbers.first?.value.stringValue,
                      !display.isEmpty,
                      !rawPhone.isEmpty
                else { return }

                let normalized = rawPhone.filter { $0.isNumber || $0 == "+" }
                let key = "\(display):\(normalized)"
                guard seen.insert(key).inserted else { return }

                // Mock "on Okaiwa" flag — every fourth contact, matches
                // the Android coin-flip exactly for parity.
                let isOnOkaiwa = (abs(normalized.hashValue) & 3) == 0
                let username = isOnOkaiwa
                    ? "@\(display.lowercased().replacingOccurrences(of: " ", with: "").prefix(12))"
                    : nil

                results.append(
                    DeviceContact(
                        id: contact.identifier,
                        displayName: display,
                        phoneNumberE164: normalized,
                        avatarData: contact.imageData,
                        isOnOkaiwa: isOnOkaiwa,
                        okaiwaUsername: username
                    )
                )
            }
        } catch {
            return []
        }

        return results
    }
}
