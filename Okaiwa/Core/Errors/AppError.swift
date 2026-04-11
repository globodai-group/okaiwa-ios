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

    var errorDescription: String? {
        switch self {
        case .server(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"

        case .timeout:
            return "The request timed out. Please check your connection and try again."

        case .noConnection:
            return "No internet connection. Please check your network settings."

        case .invalidResponse(let detail):
            return "Unexpected server response: \(detail)"

        case .encryptionFailed(let reason):
            return "Encryption error: \(reason)"

        case .keyError(let reason):
            return "Key management error: \(reason)"

        case .safetyNumberMismatch:
            return "The safety number for this contact has changed. Please verify their identity."

        case .preKeyExhausted:
            return "Unable to establish a secure session. The contact's pre-keys are exhausted."

        case .sessionExpired:
            return "Your session has expired. Please sign in again."

        case .invalidVerificationCode:
            return "The verification code is incorrect. Please try again."

        case .rateLimited(let retryAfter):
            return "Too many requests. Please wait \(retryAfter) seconds and try again."

        case .registrationDenied(let reason):
            return "Registration denied: \(reason)"

        case .transactionSigningFailed(let reason):
            return "Transaction signing failed: \(reason)"

        case .insufficientBalance(let required, let available):
            return "Insufficient balance. Required: \(required), Available: \(available)"

        case .invalidAddress(let address):
            return "Invalid address: \(address)"

        case .rpcError(let chain, let message):
            return "\(chain) network error: \(message)"

        case .cacheFailed(let reason):
            return "Local storage error: \(reason)"

        case .migrationFailed(let from, let to):
            return "Data migration failed (v\(from) -> v\(to)). Please reinstall the app."

        case .unknown(let underlying):
            return "An unexpected error occurred: \(underlying)"
        }
    }

    var failureReason: String? {
        errorDescription
    }

    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Check that Wi-Fi or cellular data is enabled."
        case .sessionExpired:
            return "Re-enter your phone number to sign in."
        case .rateLimited(let seconds):
            return "Wait \(seconds) seconds before trying again."
        case .safetyNumberMismatch:
            return "Compare safety numbers in person before continuing."
        case .insufficientBalance:
            return "Add funds to your wallet or reduce the transaction amount."
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
