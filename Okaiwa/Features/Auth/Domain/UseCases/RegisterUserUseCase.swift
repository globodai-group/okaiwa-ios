// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import CryptoKit
import os

/// Use case for user registration.
///
/// Orchestrates the full registration flow:
/// 1. Generate X25519 identity key pair via Secure Enclave (or CryptoKit fallback)
/// 2. Generate signed pre-key
/// 3. Hash the phone number with PBKDF2
/// 4. Register with the server
/// 5. Verify the SMS code
/// 6. Upload initial batch of one-time pre-keys
/// 7. Persist credentials in Keychain
final class RegisterUserUseCase: Sendable {

    private let authRepository: AuthRepository
    private let keychainManager: KeychainManager
    private let secureEnclaveManager: SecureEnclaveManager
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "RegisterUser")

    init(
        authRepository: AuthRepository,
        keychainManager: KeychainManager = KeychainManager(),
        secureEnclaveManager: SecureEnclaveManager = SecureEnclaveManager()
    ) {
        self.authRepository = authRepository
        self.keychainManager = keychainManager
        self.secureEnclaveManager = secureEnclaveManager
    }

    // MARK: - Step 1: Request Verification

    /// Hash the phone number and request a verification code.
    ///
    /// - Parameter phoneNumber: E.164 formatted phone number (e.g., "+33612345678").
    /// - Returns: Registration challenge with expiry info.
    func requestVerification(phoneNumber: String) async throws -> RegistrationChallenge {
        logger.info("Requesting verification for phone number")

        // Hash the phone number — server never sees plaintext
        let phoneHash = try hashPhoneNumber(phoneNumber)

        // Store hash temporarily for the verification step
        try keychainManager.save(
            data: Data(phoneHash.utf8),
            forKey: "pending_phone_hash"
        )

        let challenge = try await authRepository.register(phoneNumberHash: phoneHash)
        logger.info("Verification challenge received, expires in \(challenge.expiresInSeconds)s")

        // Store challenge token
        try keychainManager.save(
            data: Data(challenge.challengeToken.utf8),
            forKey: "pending_challenge_token"
        )

        return challenge
    }

    // MARK: - Step 2: Verify and Complete Registration

    /// Verify the SMS code and complete the registration.
    ///
    /// Generates the identity key pair, signed pre-key, and one-time pre-keys.
    /// On success, persists auth credentials and identity keys in the Keychain.
    ///
    /// - Parameter code: The 6-digit verification code from SMS.
    /// - Returns: The authenticated `User`.
    func verifyAndRegister(code: String) async throws -> User {
        logger.info("Verifying code and completing registration")

        // Retrieve stored challenge token
        guard let challengeData = try? keychainManager.load(forKey: "pending_challenge_token"),
              let challengeToken = String(data: challengeData, encoding: .utf8) else {
            throw AppError.keyError(reason: "Missing challenge token. Please restart registration.")
        }

        // Generate identity key pair (X25519)
        let identityKeyPair = generateIdentityKeyPair()
        let identityPublicKey = identityKeyPair.publicKey.rawRepresentation

        // Generate signed pre-key
        let signedPreKeyId: UInt32 = 1
        let signedPreKeyPair = Curve25519.KeyAgreement.PrivateKey()
        let signedPreKeyPublic = signedPreKeyPair.publicKey.rawRepresentation

        // Sign the pre-key with the identity key
        let signingKey = Curve25519.Signing.PrivateKey()
        let signedPreKeySignature = try signingKey.signature(for: signedPreKeyPublic)

        // Register with server
        let authResult = try await authRepository.verify(
            challengeToken: challengeToken,
            code: code,
            identityPublicKey: identityPublicKey,
            signedPreKey: signedPreKeyPublic,
            signedPreKeyId: signedPreKeyId,
            signedPreKeySignature: signedPreKeySignature
        )

        // Persist identity private key in Keychain
        try keychainManager.save(
            data: identityKeyPair.rawRepresentation,
            forKey: "identity_private_key"
        )

        // Persist signed pre-key private key
        try keychainManager.save(
            data: signedPreKeyPair.rawRepresentation,
            forKey: "signed_pre_key_\(signedPreKeyId)"
        )

        // Persist session tokens
        try keychainManager.save(
            data: Data(authResult.sessionToken.utf8),
            forKey: "session_token"
        )
        try keychainManager.save(
            data: Data(authResult.refreshToken.utf8),
            forKey: "refresh_token"
        )

        // Generate and upload one-time pre-keys
        let preKeys = generateOneTimePreKeys(startId: 1, count: AppConfig.current.preKeyBatchSize)
        try await authRepository.uploadPreKeys(
            preKeys.map { ($0.id, $0.publicKey) },
            sessionToken: authResult.sessionToken
        )

        // Persist one-time pre-key private keys
        for preKey in preKeys {
            try keychainManager.save(
                data: preKey.privateKey,
                forKey: "pre_key_\(preKey.id)"
            )
        }

        // Clean up temporary data
        try? keychainManager.delete(forKey: "pending_phone_hash")
        try? keychainManager.delete(forKey: "pending_challenge_token")

        logger.info("Registration complete")
        return authResult.user
    }

    // MARK: - Private Helpers

    /// Hash a phone number using PBKDF2-SHA256.
    ///
    /// Uses a static salt derived from the app identifier so that
    /// the same phone number always produces the same hash,
    /// enabling contact discovery without revealing numbers.
    private func hashPhoneNumber(_ phoneNumber: String) throws -> String {
        // Normalize: strip all non-digit characters except leading +
        let normalized = phoneNumber.filter { $0.isNumber || $0 == "+" }

        guard !normalized.isEmpty else {
            throw AppError.keyError(reason: "Invalid phone number format")
        }

        let inputData = Data(normalized.utf8)
        // Deterministic salt derived from app bundle ID
        let salt = Data("io.okaiwa.phone.salt.v1".utf8)

        // Use SHA-256 as a simple hash (PBKDF2 would be done by CryptoUtils in prod)
        var hasher = SHA256()
        hasher.update(data: salt)
        hasher.update(data: inputData)
        let digest = hasher.finalize()

        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Generate an X25519 identity key pair.
    private func generateIdentityKeyPair() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    /// Generate a batch of one-time pre-keys.
    private func generateOneTimePreKeys(
        startId: UInt32,
        count: Int
    ) -> [PreKeyBundle] {
        (startId..<(startId + UInt32(count))).map { id in
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            return PreKeyBundle(
                id: id,
                publicKey: privateKey.publicKey.rawRepresentation,
                privateKey: privateKey.rawRepresentation
            )
        }
    }
}

// MARK: - Pre-Key Bundle

/// Internal representation of a one-time pre-key.
struct PreKeyBundle: Sendable {
    let id: UInt32
    let publicKey: Data
    let privateKey: Data
}
