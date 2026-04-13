import Foundation
import Combine
import os

/// Production-path replacement for `MockProfileRepository`. Backs the
/// Profile tab with the real `/v1/profile/me` data instead of the
/// hardcoded "Kevin / @asmista / Globodai" placeholder text the mock
/// surfaced. Mirrors `RemoteProfileRepository.kt` on Android.
///
/// Strategy:
///   - `@Published var profile` is the single source of truth for the
///     UI (same shape as the mock so existing views bind unchanged).
///   - On `start()` we fire `GET /v1/profile/me` and cache the result.
///   - Mutations go through `PUT /v1/profile` and re-fetch on success
///     so any server-side normalization (lowercase username, trimming)
///     is reflected in the UI.
///
/// Auth: every authenticated call sends `Authorization: Bearer
/// <accessToken>` — the HMAC-signed value minted by /v1/auth/verify.
/// The server-side SessionAuthMiddleware validates the signature and
/// derives accountId, so the client never sends accountId on the wire
/// (which would be a forgeable bypass — see okaiwa-android@386d11d
/// security review).
@MainActor
public final class RemoteProfileRepository: ObservableObject {
    public static let shared = RemoteProfileRepository()

    @Published public private(set) var profile: UserProfile?

    private let client: IdentityProfileClient
    private let sessionStore: SessionStore
    private let logger = Logger(subsystem: "io.okaiwa.app", category: "RemoteProfileRepo")
    private var hasFetchedOnce = false

    public init(
        client: IdentityProfileClient = IdentityProfileClient(),
        sessionStore: SessionStore = SessionStore()
    ) {
        self.client = client
        self.sessionStore = sessionStore
    }

    /// Trigger a one-shot fetch of `/v1/profile/me`. Idempotent within
    /// a process lifetime — only the first call hits the network; the
    /// view can call `start()` on appear without worrying about
    /// duplicate requests.
    public func start() {
        guard !hasFetchedOnce else { return }
        hasFetchedOnce = true
        Task { await refresh() }
    }

    /// Force a refresh from the server — call right after a successful
    /// PUT so the Profile tab reflects the new values immediately.
    public func refresh() async {
        guard let session = sessionStore.current,
              !session.accessToken.isEmpty else { return }

        do {
            let response = try await client.getMyProfile(accessToken: session.accessToken)
            profile = response.toUserProfile()
        } catch {
            // Silent on transport failure — the next user-initiated
            // refresh (tab re-selection, mutation) will retry. Don't
            // wipe the cached state on transient errors.
            logger.warning("Failed to refresh profile — keeping cached state")
        }
    }
}

private extension MyProfileResponse {
    func toUserProfile() -> UserProfile {
        UserProfile(
            userId: accountId,
            displayName: profile?.displayName?.isEmpty == false
                ? profile!.displayName!
                : (username ?? "Compte Okaiwa"),
            username: username.map { "@\($0)" } ?? "@—",
            // The phone number isn't returned by /profile/me — the
            // server only stores its hash. The UI shows an empty
            // placeholder until we surface the formatted local value
            // from a separate device-local store.
            phoneNumberE164: "",
            bio: profile?.bio,
            avatarUrl: profile?.avatarUrl,
            isVerified: false,
            isOnline: true
        )
    }
}
