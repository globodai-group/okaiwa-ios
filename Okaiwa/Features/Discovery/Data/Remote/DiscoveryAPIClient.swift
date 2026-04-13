import Foundation
import os

/// URLSession-based client for the identity service discovery endpoints.
/// Mirrors `DiscoveryApi.kt` on Android.
///
/// Privacy contract enforced server-side (see okaiwa-server/identity/
/// app/controllers/discovery_controller.ts):
///   - Phone-based discovery accepts ONLY pre-hashed values.
///   - Username + wallet search are exact-match (no enumeration).
///   - Responses NEVER include the phoneHash itself.
///
/// Every response carries the recipient's `deviceId` so the sender can
/// route an encrypted blob via the relay's POST /v1/messages/send.
actor DiscoveryAPIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let baseURL: URL
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "DiscoveryAPIClient")

    init(config: AppConfig = .current, session: URLSession = .shared) {
        self.session = session
        self.baseURL = config.apiBaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func searchByUsername(_ username: String) async throws -> DiscoveredUser {
        var req = URLRequest(url: baseURL.appendingPathComponent("discovery/username/\(username)"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await fetch(req, endpoint: "discovery/username")
    }

    func searchByWallet(_ address: String) async throws -> DiscoveredUser {
        var req = URLRequest(url: baseURL.appendingPathComponent("discovery/wallet/\(address)"))
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await fetch(req, endpoint: "discovery/wallet")
    }

    func discoverByPhoneHashes(_ hashes: [String]) async throws -> PhoneHashesResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("discovery/phone-hashes"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try encoder.encode(["hashes": hashes])
        return try await fetch(req, endpoint: "discovery/phone-hashes")
    }

    private func fetch<T: Decodable>(_ req: URLRequest, endpoint: String) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AppError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(detail: "Non-HTTP response on \(endpoint)")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("\(endpoint) — decode failure: \(error.localizedDescription)")
                throw AppError.invalidResponse(detail: "Malformed \(endpoint) response")
            }
        case 404:
            throw DiscoveryError.notFound
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: body)
        }
    }
}

enum DiscoveryError: Error {
    case notFound
}

/// Public-facing slice of an Okaiwa account exposed by discovery.
///
/// No phone hash, no email, no per-session metadata. The identity public
/// key + registrationId let the sender build a Signal session against
/// this user; the deviceId routes the resulting blob to the right
/// relay inbox.
struct DiscoveredUser: Codable, Identifiable, Equatable {
    let accountId: String
    let username: String?
    let identityPublicKey: String
    let registrationId: Int
    let deviceId: String?
    let profile: DiscoveredProfile?

    var id: String { accountId }
}

struct DiscoveredProfile: Codable, Equatable {
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
}

struct PhoneHashesResponse: Codable {
    let matches: [DiscoveredUser]
    let total: Int
}
