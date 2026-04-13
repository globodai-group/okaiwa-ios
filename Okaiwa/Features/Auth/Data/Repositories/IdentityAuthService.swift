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
    private let keyClient: KeyAPIClient
    private let sessionStore: SessionStore
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "IdentityAuthService")

    init(
        client: IdentityAuthClient = IdentityAuthClient(),
        keyClient: KeyAPIClient = KeyAPIClient(),
        sessionStore: SessionStore
    ) {
        self.client = client
        self.keyClient = keyClient
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
                expiresAtEpochSeconds: 0,
                deviceId: response.deviceId ?? "",
                deviceToken: "",
                profileSetupDone: false,
                phoneE164: phoneE164
            )
        )
        logger.info("Registered — account \(response.accountId.prefix(8), privacy: .private)")
    }

    /// Login path — symmetric to [register] but only succeeds when
    /// the phone is already registered. The 404 is rethrown as
    /// `AuthClientError.accountNotFound` so the OnboardingFlow can
    /// flip the UI to a "create account with this number" CTA instead
    /// of a technical error string.
    func login(phoneE164: String) async throws {
        let phoneHash = PhoneHasher.hashE164(phoneE164)
        let response = try await client.login(LoginRequest(phoneHash: phoneHash))

        sessionStore.save(
            SessionStore.Session(
                accountId: response.accountId,
                phoneHash: phoneHash,
                accessToken: "",
                refreshToken: "",
                expiresAtEpochSeconds: 0,
                deviceId: "",
                deviceToken: "",
                profileSetupDone: false,
                phoneE164: phoneE164
            )
        )
        logger.info("Login initiated — account \(response.accountId.prefix(8), privacy: .private)")
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
                expiresAtEpochSeconds: Int64(Date().timeIntervalSince1970) + Int64(response.expiresIn),
                deviceId: response.deviceId ?? pending.deviceId,
                deviceToken: response.deviceToken ?? "",
                profileSetupDone: pending.profileSetupDone,
                phoneE164: pending.phoneE164
            )
        )
        logger.info("Verified — account \(pending.accountId.prefix(8), privacy: .private)")

        // Post-verify pre-key upload. Idempotent — `SignalIdentityKeys
        // .arePreKeysUploaded()` reads the persisted flag, so we won't
        // burn the OPK pool on every cold start. Fire-and-flag: a
        // transient failure leaves the flag unset and the next cold
        // start (via `ensurePreKeysUploaded()`) picks it up.
        await uploadPreKeysOnce(accessToken: response.sessionToken)
    }

    /// App-level warmup hook — call from the root view's `.task`
    /// (or any scope that runs once per app launch when a session is
    /// already persisted). Mirror of `RemoteAuthRepository.ensurePreKeysUploaded()`
    /// on Android. Lets pre-commit users (or anyone whose first
    /// upload failed transiently) push their kyber + OPK batch
    /// without having to re-run `/auth/verify`.
    ///
    /// Idempotent — gated by `SignalIdentityKeys.arePreKeysUploaded()`,
    /// so it's free to call eagerly on every cold start.
    func ensurePreKeysUploaded() async {
        guard let token = sessionStore.current?.accessToken, !token.isEmpty else { return }
        await uploadPreKeysOnce(accessToken: token)
    }

    /// Internal: post the initial pre-key batch to `/v1/keys/prekeys`.
    /// Idempotent via the `preKeysUploaded` flag in
    /// `SignalIdentityKeys`' Keychain-backed snapshot.
    private func uploadPreKeysOnce(accessToken: String) async {
        if SignalIdentityKeys.arePreKeysUploaded() { return }
        do {
            let batch = try SignalIdentityKeys.uploadBatch()
            let request = UploadPreKeysRequest(
                preKeys: batch.oneTimePreKeys.map {
                    PreKeyDto(keyId: $0.keyId, publicKey: $0.publicKey)
                },
                signedPreKey: batch.signedPreKey,
                kyberPreKey: batch.kyberPreKey
            )
            _ = try await keyClient.uploadPreKeys(accessToken: accessToken, body: request)
            try SignalIdentityKeys.markPreKeysUploaded()
            logger.info("prekeys uploaded (\(batch.oneTimePreKeys.count, privacy: .public) OPKs)")
        } catch {
            // Transient failure — flag stays unset so the next warmup
            // or next /auth/verify retries. NEVER let this throw up
            // to the UI: a transient pre-key upload failure is fine,
            // the session is already persisted and recoverable.
            logger.error("prekey upload failed — flag not set, will retry: \(error.localizedDescription, privacy: .public)")
        }
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
                expiresAtEpochSeconds: Int64(Date().timeIntervalSince1970) + Int64(response.expiresIn),
                // Refresh re-issues session tokens but NOT the
                // deviceToken (long-lived per relay's
                // MAX_TOKEN_AGE_SECONDS). Keep the existing one.
                deviceId: response.deviceId ?? pending.deviceId,
                deviceToken: response.deviceToken ?? pending.deviceToken,
                profileSetupDone: pending.profileSetupDone,
                phoneE164: pending.phoneE164
            )
        )
    }

    func signOut() {
        sessionStore.clear()
    }
}
