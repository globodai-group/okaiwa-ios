import Foundation
import os

/// URLSession-based client for the identity service auth endpoints.
/// Mirrors `AuthApi.kt` + `RemoteAuthRepository.kt` on Android.
///
/// Paths are relative to `AppConfig.current.apiBaseURL`, which already
/// ends with `/v1` so the calls below omit that prefix.
///
/// Every method throws an `AppError` — transport failures, 4xx/5xx HTTP
/// codes, and decoding errors all funnel through the same typed surface
/// so the ViewModels never branch on raw URLSession errors.
///
/// The session tokens returned by `verify` and `refresh` are persisted
/// by [SessionStore]. The client is stateless — it simply shuttles
/// requests and responses.
actor IdentityAuthClient {
    struct Endpoints {
        let register: URL
        let verify: URL
        let refresh: URL
        let login: URL

        init(base: URL) {
            self.register = base.appendingPathComponent("auth/register")
            self.verify = base.appendingPathComponent("auth/verify")
            self.refresh = base.appendingPathComponent("auth/refresh")
            self.login = base.appendingPathComponent("auth/login")
        }
    }

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let endpoints: Endpoints
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "IdentityAuthClient")

    init(
        config: AppConfig = .current,
        session: URLSession = .shared
    ) {
        self.session = session
        self.endpoints = Endpoints(base: config.apiBaseURL)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        self.decoder = decoder
    }

    // MARK: - Public API

    func register(_ body: RegisterRequest) async throws -> RegisterResponse {
        try await send(endpoints.register, body: body, endpoint: "register")
    }

    func verify(_ body: VerifyRequest) async throws -> SessionTokenResponse {
        try await send(endpoints.verify, body: body, endpoint: "verify")
    }

    func refresh(_ body: RefreshRequest) async throws -> SessionTokenResponse {
        try await send(endpoints.refresh, body: body, endpoint: "refresh")
    }

    /// Login request — 404 is surfaced as `AuthClientError.accountNotFound`
    /// so the UI can distinguish "this phone has no account" from other
    /// failures without sniffing error strings. The backend returns 404
    /// with body `{"error":"No account for this phone"}`.
    func login(_ body: LoginRequest) async throws -> LoginResponse {
        var request = URLRequest(url: endpoints.login)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(detail: "Non-HTTP response on login")
        }

        switch http.statusCode {
        case 200...299:
            return try decoder.decode(LoginResponse.self, from: data)
        case 404:
            throw AuthClientError.accountNotFound
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: bodyStr)
        }
    }

    // MARK: - Internals

    private func send<Body: Encodable, Output: Decodable>(
        _ url: URL,
        body: Body,
        endpoint: String
    ) async throws -> Output {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("\(endpoint) — transport failure: \(error.localizedDescription)")
            throw AppError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(detail: "Non-HTTP response on \(endpoint)")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(Output.self, from: data)
            } catch {
                logger.error("\(endpoint) — decode failure: \(error.localizedDescription)")
                throw AppError.invalidResponse(detail: "Malformed \(endpoint) response")
            }
        case 401, 403:
            throw AppError.sessionExpired
        case 409:
            throw AppError.registrationDenied(reason: "Phone already registered")
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: body)
        }
    }
}

// MARK: - DTOs (wire-format mirror of okaiwa-server/identity validators)

struct RegisterRequest: Codable {
    let phoneHash: String
    let identityPublicKey: String
    let signedPreKey: SignalIdentityKeys.SignedPreKey
    let registrationId: Int
    let username: String?
}

struct RegisterResponse: Codable {
    let accountId: String
    /// Relay-addressable device identifier (UUIDv4). Only present
    /// since the deviceId migration on the identity service.
    let deviceId: String?
    let status: String
}

struct VerifyRequest: Codable {
    let phoneHash: String
    let code: String
}

/// Response to `POST /v1/auth/verify`. The verify endpoint is the only
/// place the relay deviceToken is minted — refresh re-issues the
/// session tokens but NOT the deviceToken (which is long-lived per
/// the relay's MAX_TOKEN_AGE_SECONDS check).
struct SessionTokenResponse: Codable {
    let sessionToken: String
    let refreshToken: String
    let expiresIn: Int
    /// Relay-addressable device identifier — only present on verify.
    let deviceId: String?
    /// HMAC-signed token of the form `{deviceId}.{timestamp}.{hmac}`.
    /// Required as `Authorization: Bearer <deviceToken>` on every
    /// relay request. Only present on verify.
    let deviceToken: String?
}

struct RefreshRequest: Codable {
    let refreshToken: String
}

/// Body of POST /v1/auth/login.
struct LoginRequest: Codable {
    let phoneHash: String
}

/// 200 body of POST /v1/auth/login — 404 is raised as
/// `AuthClientError.accountNotFound` and never materializes a struct.
struct LoginResponse: Codable {
    let accountId: String
    let status: String
}

/// Typed errors the IdentityAuthClient raises when the server signal
/// deserves explicit UI handling (as opposed to generic transport /
/// validation failures funneled through AppError).
enum AuthClientError: Error {
    case accountNotFound
}
