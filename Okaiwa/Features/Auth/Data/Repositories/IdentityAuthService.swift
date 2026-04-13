import Foundation
import os

/// Thin orchestrator over [IdentityAuthClient] + [SessionStore] —
/// iOS counterpart of `RemoteAuthRepository.kt`.
///
/// The OnboardingFlow talks to THIS, not to the URLSession client
/// directly, so the Keychain persistence and the in-flight phone-hash
/// plumbing stay in one place. Both `register` and `verify` mirror the
/// Android call sites step-for-step:
///
///   1. `register(phoneE164:)` — SHA-256 the number, generate a Signal
///      key bundle, POST /v1/auth/register, stash the accountId +
///      phoneHash into the SessionStore (tokens still empty).
///   2. `verify(code:)` — pull the stashed phoneHash, POST /v1/auth/
///      verify, persist the returned access + refresh tokens.
///
/// During development the backend accepts `000000` via the
/// `DEV_SMS_BYPASS_CODE` env var so QA can run the full round-trip
/// before Brevo (SMS + email) lands.
@MainActor
final class IdentityAuthService {
    private let client: IdentityAuthClient
    private let sessionStore: SessionStore
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "IdentityAuthService")

    init(
        client: IdentityAuthClient = IdentityAuthClient(),
        sessionStore: SessionStore
    ) {
        self.client = client
        self.sessionStore = sessionStore
    }

    // MARK: - Public API

    func register(phoneE164: String) async throws {
        let phoneHash = PhoneHasher.hashE164(phoneE164)

        // Real libsignal keypair + signed pre-key. Persisted into the
        // shared `InMemorySignalProtocolStore` by `SignalIdentityKeys`
        // itself so the session layer can encrypt/decrypt later
        // without re-deriving any material.
        let bundle: SignalIdentityKeys.Bundle
        do {
            bundle = try SignalIdentityKeys.generate()
        } catch {
            logger.error("Signal key generation failed: \(error.localizedDescription, privacy: .public)")
            throw AppError.keyError(reason: error.localizedDescription)
        }

        let request = RegisterRequest(
            phoneHash: phoneHash,
            identityPublicKey: bundle.identityPublicKey,
            signedPreKey: bundle.signedPreKey,
            registrationId: bundle.registrationId,
            username: nil
        )

        let response = try await client.register(request)

        sessionStore.save(
            SessionStore.Session(
                accountId: response.accountId,
                phoneHash: phoneHash,
                accessToken: "",
                refreshToken: "",
                expiresAtEpochSeconds: 0
            )
        )
        logger.info("Registered — account \(response.accountId.prefix(8), privacy: .public)")
    }

    func verify(code: String) async throws {
        guard let pending = sessionStore.current else {
            throw AppError.sessionExpired
        }

        let response = try await client.verify(
            VerifyRequest(phoneHash: pending.phoneHash, code: code)
        )

        sessionStore.save(
            SessionStore.Session(
                accountId: pending.accountId,
                phoneHash: pending.phoneHash,
                accessToken: response.sessionToken,
                refreshToken: response.refreshToken,
                expiresAtEpochSeconds: Int64(Date().timeIntervalSince1970) + Int64(response.expiresIn)
            )
        )
        logger.info("Verified — account \(pending.accountId.prefix(8), privacy: .public)")
    }

    func refresh() async throws {
        guard let pending = sessionStore.current else {
            throw AppError.sessionExpired
        }

        let response = try await client.refresh(
            RefreshRequest(refreshToken: pending.refreshToken)
        )

        sessionStore.save(
            SessionStore.Session(
                accountId: pending.accountId,
                phoneHash: pending.phoneHash,
                accessToken: response.sessionToken,
                refreshToken: response.refreshToken,
                expiresAtEpochSeconds: Int64(Date().timeIntervalSince1970) + Int64(response.expiresIn)
            )
        )
    }

    func signOut() {
        sessionStore.clear()
    }
}
