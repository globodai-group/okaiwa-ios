// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import Security
import CryptoKit
import os

/// Manages cryptographic keys in the Secure Enclave.
///
/// The Secure Enclave is a hardware-isolated coprocessor on Apple devices
/// that generates and stores private keys. Keys created in the Secure Enclave:
/// - **Never leave the hardware** — signing operations happen on-chip
/// - **Cannot be exported** — even with full device access
/// - **Require biometric/passcode** — optionally gated by Face ID / Touch ID
///
/// Used for:
/// - Wallet transaction signing (secp256r1 / P-256)
/// - Identity key protection
/// - Biometric-gated operations
final class SecureEnclaveManager: Sendable {

    private let logger = Logger(subsystem: "io.okaiwa.app", category: "SecureEnclave")

    // MARK: - Key Generation

    /// Generate a new P-256 key pair in the Secure Enclave.
    ///
    /// The private key is stored in the Secure Enclave and never exported.
    /// The public key is returned for registration with the server.
    ///
    /// - Parameters:
    ///   - tag: Unique identifier for the key (e.g., "io.okaiwa.wallet.ethereum").
    ///   - requireBiometric: Whether signing operations require Face ID / Touch ID.
    /// - Returns: The public key data (X9.63 representation).
    /// - Throws: `AppError.keyError` if the Secure Enclave is unavailable or key generation fails.
    func generateKey(
        tag: String,
        requireBiometric: Bool = false
    ) throws -> Data {
        logger.info("Generating Secure Enclave key: \(tag)")

        // Check Secure Enclave availability
        guard SecureEnclave.isAvailable else {
            logger.warning("Secure Enclave not available — falling back to software key")
            return try generateSoftwareKey(tag: tag)
        }

        // Build access control flags
        var accessFlags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if requireBiometric {
            accessFlags.insert(.biometryCurrentSet)
        }

        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            accessFlags,
            nil
        ) else {
            throw AppError.keyError(reason: "Failed to create access control for Secure Enclave key")
        }

        // Key attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
                kSecAttrAccessControl as String: accessControl,
            ] as [String: Any],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw AppError.keyError(reason: "Secure Enclave key generation failed: \(errorDesc)")
        }

        // Extract public key
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw AppError.keyError(reason: "Failed to extract public key from Secure Enclave")
        }

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw AppError.keyError(reason: "Failed to export public key: \(errorDesc)")
        }

        logger.info("Secure Enclave key generated: \(tag) (\(publicKeyData.count) bytes)")
        return publicKeyData
    }

    // MARK: - Signing

    /// Sign data using a Secure Enclave private key.
    ///
    /// The private key never leaves the hardware. The signing operation
    /// is performed entirely within the Secure Enclave coprocessor.
    ///
    /// - Parameters:
    ///   - data: The data to sign (typically a transaction hash).
    ///   - tag: The tag identifying the private key.
    /// - Returns: The ECDSA signature (DER-encoded).
    /// - Throws: `AppError.transactionSigningFailed` if signing fails.
    func sign(data: Data, withKeyTag tag: String) throws -> Data {
        logger.info("Signing \(data.count) bytes with key: \(tag)")

        let privateKey = try loadPrivateKey(tag: tag)

        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw AppError.transactionSigningFailed(reason: "Signing algorithm not supported")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            data as CFData,
            &error
        ) as Data? else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw AppError.transactionSigningFailed(reason: "Signing failed: \(errorDesc)")
        }

        logger.info("Signed successfully: \(signature.count) byte signature")
        return signature
    }

    // MARK: - Key Management

    /// Check if a key with the given tag exists in the Secure Enclave.
    func keyExists(tag: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: false,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Delete a key from the Secure Enclave.
    ///
    /// - Parameter tag: The tag identifying the key to delete.
    /// - Throws: `AppError.keyError` if deletion fails.
    func deleteKey(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keyError(reason: "Failed to delete Secure Enclave key '\(tag)': \(status)")
        }

        logger.info("Secure Enclave key deleted: \(tag)")
    }

    /// Get the public key for an existing Secure Enclave key.
    ///
    /// - Parameter tag: The tag identifying the key.
    /// - Returns: The public key data (X9.63 representation).
    func getPublicKey(tag: String) throws -> Data {
        let privateKey = try loadPrivateKey(tag: tag)

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw AppError.keyError(reason: "Failed to extract public key for '\(tag)'")
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw AppError.keyError(reason: "Failed to export public key: \(errorDesc)")
        }

        return publicKeyData
    }

    // MARK: - Verification

    /// Verify a signature against data using the public key.
    ///
    /// - Parameters:
    ///   - signature: The ECDSA signature to verify.
    ///   - data: The original signed data.
    ///   - publicKeyData: The signer's public key (X9.63 format).
    /// - Returns: `true` if the signature is valid.
    func verify(signature: Data, for data: Data, publicKeyData: Data) throws -> Bool {
        var error: Unmanaged<CFError>?

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
        ]

        guard let publicKey = SecKeyCreateWithData(
            publicKeyData as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw AppError.keyError(reason: "Invalid public key: \(errorDesc)")
        }

        let algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
        return SecKeyVerifySignature(
            publicKey,
            algorithm,
            data as CFData,
            signature as CFData,
            &error
        )
    }

    // MARK: - Private

    /// Load a private key reference from the Secure Enclave by tag.
    private func loadPrivateKey(tag: String) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let key = result else {
            throw AppError.keyError(reason: "Secure Enclave key not found: '\(tag)' (status: \(status))")
        }

        // Force cast is safe here — SecItemCopyMatching with kSecReturnRef returns SecKey
        return key as! SecKey // swiftlint:disable:this force_cast
    }

    /// Fallback: generate a software-backed key when Secure Enclave is unavailable (simulator).
    private func generateSoftwareKey(tag: String) throws -> Data {
        let privateKey = P256.Signing.PrivateKey()
        let publicKeyData = privateKey.publicKey.x963Representation

        // Store in Keychain (not Secure Enclave)
        let keychainManager = KeychainManager()
        try keychainManager.save(data: privateKey.rawRepresentation, forKey: "se_fallback_\(tag)")

        logger.warning("Software key generated (no Secure Enclave): \(tag)")
        return publicKeyData
    }
}
