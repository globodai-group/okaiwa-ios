// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import Contacts
import CryptoKit
import os

/// Use case for discovering which of the user's phone contacts are on Okaiwa.
///
/// Privacy-preserving flow:
/// 1. Request access to the device's contact book (CNContactStore)
/// 2. Extract phone numbers from contacts
/// 3. Hash each number using PBKDF2-SHA256 with a deterministic salt
/// 4. Send the hashed batch to the identity service
/// 5. The server returns matches (users who registered with the same hash)
///
/// The server never sees plaintext phone numbers.
final class DiscoverContactsUseCase: @unchecked Sendable {

    private let contactStore = CNContactStore()
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "DiscoverContacts")

    // In production, this would be an injected IdentityService protocol
    // private let identityService: IdentityServiceProtocol

    // MARK: - Execute

    /// Discover Okaiwa users from the device's contact book.
    ///
    /// - Returns: Array of discovered contacts with their identity keys.
    func execute() async throws -> [Contact] {
        logger.info("Starting contact discovery")

        // Step 1: Request permission
        let authorized = try await requestContactAccess()
        guard authorized else {
            logger.warning("Contact access denied")
            return []
        }

        // Step 2: Fetch phone numbers from contact book
        let phoneNumbers = try fetchPhoneNumbers()
        logger.info("Found \(phoneNumbers.count) phone numbers in contact book")

        guard !phoneNumbers.isEmpty else { return [] }

        // Step 3: Hash all phone numbers
        let hashedNumbers = phoneNumbers.map { phoneEntry in
            (
                originalName: phoneEntry.name,
                hash: hashPhoneNumber(phoneEntry.number)
            )
        }
        logger.info("Hashed \(hashedNumbers.count) phone numbers for discovery")

        // Step 4: Send to identity service for matching
        let discoveredContacts = try await discoverOnServer(
            hashes: hashedNumbers.map(\.hash)
        )

        logger.info("Discovered \(discoveredContacts.count) Okaiwa users")
        return discoveredContacts
    }

    /// Check if the app has contact access permission.
    var hasContactPermission: Bool {
        CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    // MARK: - Private

    /// Request access to the device's Contacts.
    private func requestContactAccess() async throws -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            return true

        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }

        case .denied, .restricted:
            return false

        @unknown default:
            return false
        }
    }

    /// Fetch all phone numbers from the device's contact book.
    private func fetchPhoneNumbers() throws -> [(name: String, number: String)] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .userDefault

        var results: [(name: String, number: String)] = []

        try contactStore.enumerateContacts(with: request) { contact, _ in
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)

            for phoneNumber in contact.phoneNumbers {
                let number = phoneNumber.value.stringValue
                let normalized = self.normalizePhoneNumber(number)

                if !normalized.isEmpty {
                    results.append((name: name, number: normalized))
                }
            }
        }

        return results
    }

    /// Normalize a phone number to E.164 format.
    ///
    /// Strips whitespace, dashes, parentheses. Ensures leading +.
    private func normalizePhoneNumber(_ number: String) -> String {
        var cleaned = number.filter { $0.isNumber || $0 == "+" }

        // Ensure it starts with +
        if !cleaned.hasPrefix("+") && cleaned.count >= 10 {
            // Assume local format — in production, use country code detection
            cleaned = "+\(cleaned)"
        }

        return cleaned
    }

    /// Hash a phone number using SHA-256 with a deterministic salt.
    ///
    /// In production, this should use PBKDF2-SHA256 with a high iteration count
    /// via the CryptoUtils package. SHA-256 is used here as a placeholder.
    private func hashPhoneNumber(_ phoneNumber: String) -> String {
        let inputData = Data(phoneNumber.utf8)
        let salt = Data("io.okaiwa.phone.salt.v1".utf8)

        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: inputData)
        let digest = hasher.finalize()

        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Send hashed phone numbers to the identity service for matching.
    ///
    /// The server checks which hashes correspond to registered users
    /// and returns their public identity information.
    private func discoverOnServer(hashes: [String]) async throws -> [Contact] {
        // In production: POST /v1/identity/discover with { "hashes": [...] }
        // Server returns matching users with their public keys

        // Batch in groups of 1000 to avoid payload limits
        var allDiscovered: [Contact] = []

        let batchSize = 1000
        for batchStart in stride(from: 0, to: hashes.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, hashes.count)
            let batch = Array(hashes[batchStart..<batchEnd])

            // TODO: Call identityService.discover(hashes: batch)
            _ = batch
            logger.debug("Sent batch \(batchStart/batchSize + 1) (\(batch.count) hashes)")
        }

        return allDiscovered
    }
}
