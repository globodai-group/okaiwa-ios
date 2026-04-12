import Foundation

/// Device address-book access — mirrors `DeviceContactsRepository.kt`.
///
/// Callers must hold `Contacts` authorization before calling
/// `loadContacts()`; without authorization the implementation returns
/// an empty list.
public protocol DeviceContactsRepository: Sendable {
    func loadContacts() async -> [DeviceContact]
}
