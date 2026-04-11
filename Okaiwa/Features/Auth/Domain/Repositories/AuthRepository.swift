// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Repository protocol for authentication operations.
///
/// Implementations handle:
/// - Phone number registration and SMS verification
/// - Identity key upload (Signal Protocol)
/// - Pre-key bundle management
/// - Session lifecycle (refresh, logout, revocation)
///
/// All methods are async and throw `AppError` on failure.
protocol AuthRepository: Sendable {

    /// Request an SMS verification code for the given phone number hash.
    ///
    /// The phone number is hashed client-side (PBKDF2-SHA256) before sending.
    /// The server never sees the plaintext phone number.
    ///
    /// - Parameter phoneNumberHash: PBKDF2 hash of the E.164 phone number.
    /// - Returns: A challenge token to be used with `verifyCode`.
    /// - Throws: `AppError.rateLimited` if too many requests.
    func register(phoneNumberHash: String) async throws -> RegistrationChallenge

    /// Verify the SMS code and complete registration.
    ///
    /// On success, the server creates the account and returns an auth token.
    ///
    /// - Parameters:
    ///   - challengeToken: The token from `register()`.
    ///   - code: The 6-digit SMS verification code.
    ///   - identityPublicKey: The user's X25519 identity public key.
    ///   - signedPreKey: The signed pre-key public component.
    ///   - signedPreKeySignature: Signature over the signed pre-key.
    /// - Returns: The authenticated `User` and session token.
    func verify(
        challengeToken: String,
        code: String,
        identityPublicKey: Data,
        signedPreKey: Data,
        signedPreKeyId: UInt32,
        signedPreKeySignature: Data
    ) async throws -> AuthResult

    /// Set the username for a newly registered account.
    ///
    /// - Parameters:
    ///   - username: Desired username (3-32 chars, alphanumeric + underscores).
    ///   - sessionToken: Active session token.
    /// - Throws: `AppError.server` if username is taken.
    func setUsername(_ username: String, sessionToken: String) async throws

    /// Upload a batch of one-time pre-keys to the server.
    ///
    /// The server distributes these to contacts establishing new sessions.
    /// Should be called when the server's pre-key count drops below threshold.
    ///
    /// - Parameters:
    ///   - preKeys: Array of (id, publicKey) tuples.
    ///   - sessionToken: Active session token.
    func uploadPreKeys(
        _ preKeys: [(id: UInt32, publicKey: Data)],
        sessionToken: String
    ) async throws

    /// Refresh the session token using the stored refresh token.
    ///
    /// - Parameter refreshToken: The long-lived refresh token.
    /// - Returns: New session and refresh tokens.
    func refreshSession(refreshToken: String) async throws -> TokenPair

    /// Log out and invalidate the current session.
    ///
    /// Deletes the session on the server and clears local auth state.
    ///
    /// - Parameter sessionToken: The session token to invalidate.
    func logout(sessionToken: String) async throws

    /// Check the remaining pre-key count on the server.
    ///
    /// - Parameter sessionToken: Active session token.
    /// - Returns: Number of unused one-time pre-keys available.
    func preKeyCount(sessionToken: String) async throws -> Int
}

// MARK: - Supporting Types

/// Challenge returned by the server after registration request.
struct RegistrationChallenge: Codable, Sendable {
    /// Token to submit with the verification code.
    let challengeToken: String
    /// Number of seconds until the code expires.
    let expiresInSeconds: Int
    /// Number of digits in the verification code.
    let codeLength: Int
}

/// Result of successful authentication.
struct AuthResult: Codable, Sendable {
    let user: User
    let sessionToken: String
    let refreshToken: String
    let expiresAt: Date
}

/// Pair of tokens returned on refresh.
struct TokenPair: Codable, Sendable {
    let sessionToken: String
    let refreshToken: String
    let expiresAt: Date
}
