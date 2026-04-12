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

                // Flag filled in after the enumeration completes so the
                // cohort size is known (see below).
                results.append(
                    DeviceContact(
                        id: contact.identifier,
                        displayName: display,
                        phoneNumberE164: normalized,
                        avatarData: contact.imageData,
                        isOnOkaiwa: false,
                        okaiwaUsername: nil
                    )
                )
            }
        } catch {
            return []
        }

        // Mock "on Okaiwa" split — flip the first 8 entries to Okaiwa
        // users. Mirrors `AndroidDeviceContactsRepository.kt`. The
        // previous `hashValue & 3 == 0` coin-flip was unstable across
        // platforms and phone-number distributions, flagging the whole
        // address book on some devices.
        var cohort = results.prefix(8).map { c -> DeviceContact in
            DeviceContact(
                id: c.id,
                displayName: c.displayName,
                phoneNumberE164: c.phoneNumberE164,
                avatarData: c.avatarData,
                isOnOkaiwa: true,
                okaiwaUsername: "@" + c.displayName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "")
                    .prefix(12)
            )
        }
        cohort.append(contentsOf: results.dropFirst(8))
        return cohort
    }
}
