// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 Globodai FZCO

import Foundation
import os

/// URLSession-based client for the relay (store-and-forward inbox) —
/// iOS twin of `RelayApi.kt` on Android.
///
/// Auth: EVERY endpoint requires `Authorization: Bearer <deviceToken>`
/// from `SessionStore`. The deviceToken is `{deviceId}.{timestamp}.
/// {hmac}` minted by `/v1/auth/verify` — distinct from the accessToken
/// the identity service consumes.
///
/// Endpoints:
///   - `POST /v1/messages/send`       — enqueue one ciphertext envelope.
///   - `GET /v1/messages/pending`     — pull every enqueued envelope;
///     the AdonisJS validator on the server reads the deviceId from
///     the REQUEST BODY, so we attach a body to the GET (legal per
///     RFC 7231 §4.3.1 but unusual; URLSession happily does this).
///   - `DELETE /v1/messages/:id`      — ack + purge after local persist.
actor RelayAPIClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "RelayAPIClient")

    init(config: AppConfig = .current, session: URLSession = .shared) {
        self.session = session
        self.baseURL = config.apiBaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Enqueue a ciphertext envelope for the recipient's device.
    /// The bearer here is the long-lived deviceToken, NOT the
    /// sessionToken — the relay validates them against different
    /// HMAC keys.
    func sendMessage(
        deviceToken: String,
        body: SendMessageRequest
    ) async throws -> SendMessageResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("messages/send"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)
        return try await send(request, endpoint: "messages/send")
    }

    /// Pull every enqueued envelope for a device. The backend validator
    /// wants the deviceId in the body on a GET (odd but legal — we
    /// mirror what Android does). URLSession accepts a body on GET
    /// without complaining; no NSURLSession quirk like OkHttp to
    /// work around.
    func getPending(
        deviceToken: String,
        body: PendingMessagesRequest
    ) async throws -> PendingMessagesResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("messages/pending"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try encoder.encode(body)
        return try await send(request, endpoint: "messages/pending")
    }

    /// Ack + purge an envelope from the relay inbox. Best-effort —
    /// 204 / 404 are both terminal. Any other code re-enters the poll
    /// cycle naturally.
    func deleteMessage(
        deviceToken: String,
        messageId: String
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("messages/\(messageId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            logger.error("delete — transport failure: \(error.localizedDescription, privacy: .public)")
            throw AppError.from(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(detail: "Non-HTTP response on messages/delete")
        }
        switch http.statusCode {
        case 200...299, 404:
            return
        case 401, 403:
            throw AppError.sessionExpired
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            throw AppError.server(statusCode: http.statusCode, message: "messages/delete HTTP \(http.statusCode)")
        }
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
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: bodyStr)
        }
    }
}

// MARK: - Wire format (mirrors RelayApi.kt exactly)

/// Body of `POST /v1/messages/send`. The backend cross-checks
/// `senderDeviceId` against the deviceToken's deviceId — any mismatch
/// is a forged envelope attempt. `senderAccountId` lets the receiver
/// route the decrypted payload to the right SignalProtocolAddress
/// without a second lookup on the relay.
struct SendMessageRequest: Codable, Equatable, Sendable {
    let recipientDeviceId: String
    /// Base64 of the libsignal CiphertextMessage serialisation.
    let blob: String
    /// Client-generated idempotency key (UUID).
    let messageId: String
    /// Sender's device id — cross-checked server-side against the
    /// deviceToken. Landed with the validator revision the Android
    /// side pushed in dc897f1.
    let senderDeviceId: String
    /// Sender's account id — landed alongside senderDeviceId so the
    /// receiver can resolve the address without re-fetching.
    let senderAccountId: String
}

struct SendMessageResponse: Codable, Equatable, Sendable {
    let status: String
    let messageId: String?
}

struct PendingMessagesRequest: Codable, Equatable, Sendable {
    let deviceId: String
}

struct PendingMessagesResponse: Codable, Equatable, Sendable {
    let messages: [RelayEnvelope]
    let count: Int
}

struct RelayEnvelope: Codable, Equatable, Sendable {
    let messageId: String
    /// Base64 of the libsignal CiphertextMessage.
    let blob: String
    let enqueuedAt: Int64
    /// Sender's device id — the relay injects it so the receiver can
    /// bind the session to the right SignalProtocolAddress. If
    /// absent, the caller skips (at-least-once re-delivers the
    /// envelope on the next poll once the backend catches up).
    let senderDeviceId: String?
    let senderAccountId: String?
}
