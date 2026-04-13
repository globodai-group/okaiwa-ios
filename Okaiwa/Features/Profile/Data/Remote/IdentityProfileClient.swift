import Foundation
import os

/// URLSession-based client for the identity service profile endpoint.
/// Mirrors `ProfileApi.kt` on Android.
///
/// Authentication: the server currently reads `x-account-id` from the
/// request header instead of validating a session token — the proper
/// auth middleware + sessions table land with the next migration.
/// Until then the iOS client passes the stashed accountId explicitly.
actor IdentityProfileClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "IdentityProfileClient")

    init(config: AppConfig = .current, session: URLSession = .shared) {
        self.session = session
        self.baseURL = config.apiBaseURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// PUT /v1/profile — partial update. Pass only the fields the user
    /// changed; the server keeps the rest as-is.
    func updateProfile(
        accountId: String,
        body: UpdateProfileRequest
    ) async throws -> UpdateProfileResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("profile"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Okaiwa-iOS/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(accountId, forHTTPHeaderField: "x-account-id")
        request.httpBody = try encoder.encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AppError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.invalidResponse(detail: "Non-HTTP response on profile")
        }

        switch http.statusCode {
        case 200...299:
            return try decoder.decode(UpdateProfileResponse.self, from: data)
        case 409:
            throw ProfileClientError.usernameTaken
        case 429:
            throw AppError.rateLimited(retryAfterSeconds: 30)
        default:
            let bodyStr = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AppError.server(statusCode: http.statusCode, message: bodyStr)
        }
    }
}

enum ProfileClientError: Error {
    case usernameTaken
}

/// Body of PUT /v1/profile. All fields are optional — the server
/// accepts partial updates so the client can set, say, just a username
/// at profile-setup time and defer the avatar to later.
struct UpdateProfileRequest: Codable {
    var username: String?
    var displayName: String?
    var bio: String?
    var avatarUrl: String?
    var visibility: String?
    var exposedWalletAddresses: [String]?
}

struct UpdateProfileResponse: Codable {
    let accountId: String
    let username: String?
    let profile: UpdatedProfile?
}

struct UpdatedProfile: Codable {
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let visibility: String?
    let exposedWalletAddresses: [String]?
}
