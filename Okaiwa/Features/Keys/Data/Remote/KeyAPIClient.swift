// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// URLSession-based client for the identity service pre-key endpoints.
/// iOS twin of `KeyApi.kt` on Android — every DTO below mirrors the
/// kotlinx-serialization shape the backend already accepts.
///
/// Two responsibilities:
///   1. `POST /v1/keys/prekeys` — upload our one-time pre-key batch +
///      signed pre-key + (PQXDH) kyber pre-key after OTP verify. Auth:
///      `Authorization: Bearer <accessToken>` from `SessionStore`. The
///      server derives accountId from the token — NEVER put an
///      accountId header in the request, that is a forgeable bypass
///      that was closed on Android in the P0 security review.
///   2. `GET /v1/keys/prekey/:deviceId` — anonymous lookup that
///      returns ONE one-time pre-key (consumed server-side) + the
///      signed pre-key + identity key + registrationId for the target
///      device. No auth required — the deviceId is the routing handle.
///
/// The client tolerates a null `preKey` on the fetch (server out of
/// OPKs) and a null `kyberPreKey` (peer pre-commit of the kyber
/// landing); the chat layer decides whether to defer the send.
actor KeyAPIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "KeyAPIClient")

    init(config: AppConfig = .current, session: URLSession = .shared) {
        self.session = session
        self.baseURL = config.apiBaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Upload the initial pre-key batch. Bearer is the access token
    /// minted by `/v1/auth/verify`; the server derives accountId from
    /// the token so we never put an accountId header on the request.
    func uploadPreKeys(
        accessToken: String,
        body: UploadPreKeysRequest
    ) async throws -> UploadPreKeysResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("keys/prekeys"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)

        return try await send(request, endpoint: "keys/prekeys")
    }

    /// Anonymous peer bundle lookup. The returned shape matches the
    /// PreKeyBundle libsignal needs to drive SessionBuilder.
    func fetchPreKey(deviceId: String) async throws -> FetchPreKeyResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("keys/prekey/\(deviceId)"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")

        return try await send(request, endpoint: "keys/prekey")
    }

    // MARK: - Internals

    private func send<Output: Decodable>(
        _ request: URLRequest,
        endpoint: String
    ) async throws -> Output {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger.error("\(endpoint) — transport failure: \(error.localizedDescription, privacy: .public)")
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
                logger.error("\(endpoint) — decode failure: \(error.localizedDescription, privacy: .public)")
                throw AppError.invalidResponse(detail: "Malformed \(endpoint) response")
            }
        case 401, 403:
            throw AppError.sessionExpired
        case 404:
            throw KeyAPIError.notFound
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: bodyStr)
        }
    }
}

/// Typed errors surfaced by the key API beyond the generic AppError
/// funnel — the chat layer branches on `.notFound` to surface a "peer
/// has no bundle yet" hint instead of a transport error.
enum KeyAPIError: Error, Equatable {
    case notFound
}

// MARK: - Wire format (mirrors okaiwa-server/identity validators + KeyApi.kt)

/// Single one-time pre-key public key + id. Mirrors `PreKeyDto` on Android.
struct PreKeyDto: Codable, Equatable, Sendable {
    let keyId: Int
    let publicKey: String
}

/// Kyber (PQXDH) pre-key public key + the signature from the identity
/// key. Mirrors `KyberPreKeyDto` on Android.
struct KyberPreKeyDto: Codable, Equatable, Sendable {
    let keyId: Int
    let publicKey: String
    let signature: String
}

/// Body of `POST /v1/keys/prekeys`. Mirrors `UploadPreKeysRequest.kt`.
struct UploadPreKeysRequest: Codable, Equatable, Sendable {
    /// 1..100 one-time pre-keys.
    let preKeys: [PreKeyDto]
    /// Optional signed pre-key refresh. Sent unconditionally on first
    /// upload so the server has the same record we persisted locally.
    let signedPreKey: SignalIdentityKeys.SignedPreKey?
    /// Kyber (PQXDH) pre-key. Required for libsignal 0.86+ session
    /// setup.
    let kyberPreKey: KyberPreKeyDto?
}

/// Response of `POST /v1/keys/prekeys`.
struct UploadPreKeysResponse: Codable, Equatable, Sendable {
    let status: String
    /// Server-echoed count of stored OPKs. Defaults to 0 so a backend
    /// revision that omits the field doesn't break decoding.
    let storedPreKeyCount: Int?
}

/// Response of `GET /v1/keys/prekey/:deviceId`. Fields map 1:1 onto
/// libsignal's `PreKeyBundle` initializers.
struct FetchPreKeyResponse: Codable, Equatable, Sendable {
    /// Base64-encoded Curve25519 public key of the peer's identity.
    let identityKey: String
    let registrationId: Int
    /// Optional — some backend revisions omit this, we accept either
    /// shape to stay byte-compatible with Android.
    let deviceId: String?
    let signedPreKey: SignalIdentityKeys.SignedPreKey
    /// Null when the peer has run out of OPKs. Caller falls back to a
    /// signed-pre-key-only PreKeyBundle — libsignal has a dedicated
    /// initializer for that shape.
    let preKey: PreKeyDto?
    /// Kyber (PQXDH) pre-key. Null when the peer hasn't uploaded a
    /// kyber yet (pre-commit user) — caller defers the send instead
    /// of building a broken session.
    let kyberPreKey: KyberPreKeyDto?
}
