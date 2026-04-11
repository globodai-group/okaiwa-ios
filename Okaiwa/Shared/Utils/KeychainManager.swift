// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import Security
import os

/// Secure Keychain wrapper for storing sensitive data.
///
/// All items are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`,
/// meaning they are:
/// - Only accessible when the device is unlocked
/// - Not included in device backups
/// - Not migrated to a new device
///
/// This ensures that identity keys, session tokens, and wallet seeds
/// are bound to the physical device and cannot be extracted.
final class KeychainManager: Sendable {

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "Keychain")
    private let service: String
    private let accessGroup: String?

    /// Initialize with the app's Keychain service identifier.
    ///
    /// - Parameters:
    ///   - service: Keychain service name (default: bundle ID).
    ///   - accessGroup: Optional Keychain access group for app extensions.
    init(
        service: String = "io.okaiwa.keychain",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup
    }

    // MARK: - CRUD Operations

    /// Save data to the Keychain.
    ///
    /// If an item with the given key already exists, it will be updated.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The unique key for this item.
    /// - Throws: `AppError.cacheFailed` if the operation fails.
    func save(data: Data, forKey key: String) throws {
        // Try to update first
        let updateQuery = baseQuery(forKey: key)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            logger.debug("Keychain item updated: \(key, privacy: .private)")
            return
        }

        if updateStatus != errSecItemNotFound {
            // Some other error during update
            throw AppError.cacheFailed(reason: "Keychain update failed for '\(key)': \(updateStatus)")
        }

        // Item doesn't exist — add it
        var addQuery = baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw AppError.cacheFailed(reason: "Keychain save failed for '\(key)': \(addStatus)")
        }

        logger.debug("Keychain item saved: \(key, privacy: .private)")
    }

    /// Load data from the Keychain.
    ///
    /// - Parameter key: The key to look up.
    /// - Returns: The stored data, or `nil` if the key doesn't exist.
    /// - Throws: `AppError.cacheFailed` if the operation fails (not for missing keys).
    func load(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw AppError.cacheFailed(reason: "Keychain returned non-data for '\(key)'")
            }
            return data

        case errSecItemNotFound:
            return nil

        default:
            throw AppError.cacheFailed(reason: "Keychain load failed for '\(key)': \(status)")
        }
    }

    /// Delete an item from the Keychain.
    ///
    /// - Parameter key: The key to delete.
    /// - Throws: `AppError.cacheFailed` if the deletion fails.
    func delete(forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.cacheFailed(reason: "Keychain delete failed for '\(key)': \(status)")
        }

        logger.debug("Keychain item deleted: \(key, privacy: .private)")
    }

    /// Check if an item exists in the Keychain.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if the item exists.
    func exists(forKey key: String) -> Bool {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete all items for this service.
    ///
    /// Use with caution — this removes all stored keys and tokens.
    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.cacheFailed(reason: "Keychain deleteAll failed: \(status)")
        }

        logger.warning("All Keychain items deleted for service: \(self.service)")
    }

    // MARK: - Convenience

    /// Save a string to the Keychain.
    func saveString(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw AppError.cacheFailed(reason: "Failed to encode string for '\(key)'")
        }
        try save(data: data, forKey: key)
    }

    /// Load a string from the Keychain.
    func loadString(forKey key: String) throws -> String? {
        guard let data = try load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private

    /// Build the base query dictionary for a Keychain operation.
    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
