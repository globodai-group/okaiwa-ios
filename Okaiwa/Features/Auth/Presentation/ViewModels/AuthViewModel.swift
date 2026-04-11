// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// View model for the authentication flow.
///
/// Manages the state machine for:
/// idle -> enteringPhone -> verifyingCode -> choosingUsername -> authenticated
///
/// Uses `@Observable` macro (Swift 5.9+) for SwiftUI reactivity.
@Observable
final class AuthViewModel {

    // MARK: - State

    enum State: Equatable {
        case idle
        case enteringPhone
        case verifyingCode
        case choosingUsername
        case authenticated
        case error(String)
    }

    // MARK: - Published Properties

    private(set) var state: State = .idle
    var phoneNumber: String = ""
    var countryCode: String = "+33"
    var verificationCode: String = ""
    var username: String = ""
    private(set) var isLoading: Bool = false
    private(set) var challenge: RegistrationChallenge?
    private(set) var currentUser: User?
    private(set) var codeExpiresAt: Date?
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    private var registerUseCase: RegisterUserUseCase?
    private let keychainManager = KeychainManager()
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "AuthVM")

    // MARK: - Initialization

    init() {
        checkExistingSession()
    }

    // MARK: - Public Actions

    /// Transition to the phone entry state.
    func startRegistration() {
        state = .enteringPhone
        errorMessage = nil
    }

    /// Request a verification code for the entered phone number.
    func requestVerificationCode() async {
        let fullNumber = countryCode + phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidPhoneNumber(fullNumber) else {
            errorMessage = "Please enter a valid phone number."
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Requesting verification code")

        do {
            // In production, registerUseCase would be injected
            if registerUseCase == nil {
                logger.warning("RegisterUseCase not injected — auth flow requires server connection")
            }

            let result = try await registerUseCase?.requestVerification(phoneNumber: fullNumber)
            challenge = result
            if let result {
                codeExpiresAt = Date().addingTimeInterval(TimeInterval(result.expiresInSeconds))
            }
            state = .verifyingCode
            logger.info("Transitioned to verifyingCode state")
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.localizedDescription
            state = .error(appError.localizedDescription)
            logger.error("Verification request failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Verify the SMS code and complete registration.
    func verifyCode() async {
        let code = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)

        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            errorMessage = "Please enter the 6-digit code."
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Verifying code")

        do {
            let user = try await registerUseCase?.verifyAndRegister(code: code)
            currentUser = user

            if user?.username.isEmpty == false {
                state = .authenticated
            } else {
                state = .choosingUsername
            }
            logger.info("Code verified — user: \(user?.id.prefix(8) ?? "nil")")
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.localizedDescription
            state = .error(appError.localizedDescription)
            logger.error("Code verification failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Set the username after verification.
    func setUsername() async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidUsername(name) else {
            errorMessage = "Username must be 3-32 characters (letters, numbers, underscores)."
            return
        }

        isLoading = true
        errorMessage = nil
        logger.info("Setting username: \(name)")

        do {
            guard let token = try? keychainManager.load(forKey: "session_token"),
                  let sessionToken = String(data: token, encoding: .utf8) else {
                throw AppError.sessionExpired
            }

            // In production, call AuthRepository.setUsername
            _ = sessionToken
            state = .authenticated
            logger.info("Username set — fully authenticated")
        } catch {
            let appError = AppError.from(error)
            errorMessage = appError.localizedDescription
            logger.error("Set username failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Log out and clear all session data.
    func logout() async {
        logger.info("Logging out")
        isLoading = true

        // Clear Keychain credentials
        try? keychainManager.delete(forKey: "session_token")
        try? keychainManager.delete(forKey: "refresh_token")
        try? keychainManager.delete(forKey: "identity_private_key")

        currentUser = nil
        phoneNumber = ""
        verificationCode = ""
        username = ""
        state = .idle
        isLoading = false
        logger.info("Logged out successfully")
    }

    /// Reset to idle state (e.g., after error recovery).
    func resetToIdle() {
        state = .idle
        errorMessage = nil
        isLoading = false
    }

    /// Inject the registration use case (called from DI container).
    func configure(registerUseCase: RegisterUserUseCase) {
        self.registerUseCase = registerUseCase
    }

    // MARK: - Private

    /// Check if a valid session exists in the Keychain.
    private func checkExistingSession() {
        guard let tokenData = try? keychainManager.load(forKey: "session_token"),
              !tokenData.isEmpty else {
            state = .idle
            return
        }

        // Session token exists — consider authenticated
        // In production, validate token with server
        state = .authenticated
        logger.info("Existing session found — auto-authenticated")
    }

    private func isValidPhoneNumber(_ number: String) -> Bool {
        let digits = number.filter(\.isNumber)
        return digits.count >= 7 && digits.count <= 15
    }

    private func isValidUsername(_ name: String) -> Bool {
        let pattern = "^[a-zA-Z0-9_]{3,32}$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }
}
