import Contacts
import Foundation
import Observation

public enum ContactPermissionState {
    case unknown
    case granted
    case denied
}

/// ViewModel backing `ContactPickerView` — mirrors `ContactsViewModel.kt`.
@Observable
public final class ContactsViewModel {
    public var permissionState: ContactPermissionState = .unknown
    public var isLoading: Bool = false
    public var query: String = ""
    public private(set) var allContacts: [DeviceContact] = []

    private let repository: DeviceContactsRepository
    private let store = CNContactStore()

    public init(repository: DeviceContactsRepository = IOSDeviceContactsRepository()) {
        self.repository = repository
    }

    public func requestAccess() {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            permissionState = .granted
            Task { await loadContacts() }
        case .denied, .restricted:
            permissionState = .denied
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionState = granted ? .granted : .denied
                    if granted { Task { await self.loadContacts() } }
                }
            }
        @unknown default:
            permissionState = .denied
        }
    }

    public var filtered: [DeviceContact] {
        guard !query.isEmpty else { return allContacts }
        let digits = query.filter { $0.isNumber || $0 == "+" }
        return allContacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            (!digits.isEmpty && $0.phoneNumberE164.contains(digits))
        }
    }

    public var okaiwaContacts: [DeviceContact] { filtered.filter { $0.isOnOkaiwa } }
    public var inviteContacts: [DeviceContact] { filtered.filter { !$0.isOnOkaiwa } }

    @MainActor
    private func loadContacts() async {
        isLoading = true
        let result = await repository.loadContacts()
        allContacts = result
        isLoading = false
    }
}
