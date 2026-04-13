// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation

/// Unified error type for the Okaiwa application.
///
/// All domain errors are funneled through this enum so that
/// presentation layers can display localized, user-friendly messages
/// without leaking implementation details.
enum AppError: Error, LocalizedError, Equatable, Sendable {

    // MARK: - Network

    /// Server returned an error status code.
    case server(statusCode: Int, message: String)

    /// Request timed out.
    case timeout

    /// No network connectivity.
    case noConnection

    /// Invalid server response (unexpected format, missing fields).
    case invalidResponse(detail: String)

    // MARK: - Cryptography

    /// Signal Protocol encryption or decryption failure.
    case encryptionFailed(reason: String)

    /// Key generation, derivation, or storage error.
    case keyError(reason: String)

    /// Safety number verification failed.
    case safetyNumberMismatch

    /// Pre-key bundle exhausted or unavailable.
    case preKeyExhausted

    // MARK: - Authentication

    /// Session expired — user must re-authenticate.
    case sessionExpired

    /// Invalid verification code.
    case invalidVerificationCode

    /// Rate limited by server.
    case rateLimited(retryAfterSeconds: Int)

    /// Registration denied.
    case registrationDenied(reason: String)

    // MARK: - Wallet

    /// Transaction signing failed.
    case transactionSigningFailed(reason: String)

    /// Insufficient balance for the requested transaction.
    case insufficientBalance(required: String, available: String)

    /// Invalid wallet address.
    case invalidAddress(address: String)

    /// RPC node error.
    case rpcError(chain: String, message: String)

    // MARK: - Local Storage

    /// SQLCipher or Keychain read/write failure.
    case cacheFailed(reason: String)

    /// Data migration error.
    case migrationFailed(from: Int, to: Int)

    // MARK: - General

    /// An error that doesn't fit other categories.
    case unknown(underlying: String)

    // MARK: - LocalizedError

    /// Look up a format string from the Core module bundle. All error
    /// copy lives in `OkaiwaCore/Resources/*.lproj/Localizable.strings`
    /// — this helper keeps the `NSLocalizedString` / `bundle: .module`
    /// boilerplate out of every case branch.
    private static func loc(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
    }

    var errorDescription: String? {
        switch self {
        case .server(let statusCode, let message):
            return String(format: Self.loc("error_server_format"), statusCode, message)

        case .timeout:
            return Self.loc("error_timeout")

        case .noConnection:
            return Self.loc("error_no_connection")

        case .invalidResponse(let detail):
            return String(format: Self.loc("error_invalid_response_format"), detail)

        case .encryptionFailed(let reason):
            return String(format: Self.loc("error_encryption_failed_format"), reason)

        case .keyError(let reason):
            return String(format: Self.loc("error_key_format"), reason)

        case .safetyNumberMismatch:
            return Self.loc("error_safety_number_mismatch")

        case .preKeyExhausted:
            return Self.loc("error_prekey_exhausted")

        case .sessionExpired:
            return Self.loc("error_session_expired")

        case .invalidVerificationCode:
            return Self.loc("error_invalid_verification_code")

        case .rateLimited(let retryAfter):
            return String(format: Self.loc("error_rate_limited_format"), retryAfter)

        case .registrationDenied(let reason):
            return String(format: Self.loc("error_registration_denied_format"), reason)

        case .transactionSigningFailed(let reason):
            return String(format: Self.loc("error_tx_signing_failed_format"), reason)

        case .insufficientBalance(let required, let available):
            return String(format: Self.loc("error_insufficient_balance_format"), required, available)

        case .invalidAddress(let address):
            return String(format: Self.loc("error_invalid_address_format"), address)

        case .rpcError(let chain, let message):
            return String(format: Self.loc("error_rpc_format"), chain, message)

        case .cacheFailed(let reason):
            return String(format: Self.loc("error_cache_failed_format"), reason)

        case .migrationFailed(let from, let to):
            return String(format: Self.loc("error_migration_failed_format"), from, to)

        case .unknown(let underlying):
            return String(format: Self.loc("error_unknown_format"), underlying)
        }
    }

    var failureReason: String? {
        errorDescription
    }

    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return Self.loc("error_recovery_no_connection")
        case .sessionExpired:
            return Self.loc("error_recovery_session_expired")
        case .rateLimited(let seconds):
            return String(format: Self.loc("error_recovery_rate_limited_format"), seconds)
        case .safetyNumberMismatch:
            return Self.loc("error_recovery_safety_number")
        case .insufficientBalance:
            return Self.loc("error_recovery_insufficient_balance")
        default:
            return nil
        }
    }

    // MARK: - Equatable (for state comparison in ViewModels)

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}

// MARK: - Convenience Initializer

extension AppError {

    /// Wrap any `Error` into an `AppError`.
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError

        // URLSession errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost:
                return .noConnection
            default:
                return .unknown(underlying: error.localizedDescription)
            }
        }

        return .unknown(underlying: error.localizedDescription)
    }
}
