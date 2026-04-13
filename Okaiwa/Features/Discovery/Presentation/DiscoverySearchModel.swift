import Foundation
import Observation

/// Backs the inline search field on `NewMessageView`. Mirrors
/// `DiscoverySearchViewModel.kt`. The user types a username (with or
/// without leading `@`) and we hit `GET /v1/discovery/username/:username`
/// after a 300 ms idle window so we don't spam the backend on every
/// keystroke.
@Observable
@MainActor
final class DiscoverySearchModel {
    enum State: Equatable {
        case idle
        case searching
        case found(DiscoveredUser)
        case notFound
        case error(String)
    }

    private(set) var state: State = .idle

    private let client: DiscoveryAPIClient
    private var debounceTask: Task<Void, Never>?

    init(client: DiscoveryAPIClient = DiscoveryAPIClient()) {
        self.client = client
    }

    func onQueryChanged(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        debounceTask?.cancel()

        guard query.count >= 3 else {
            state = .idle
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.state = .searching
            do {
                let user = try await self.client.searchByUsername(query)
                if !Task.isCancelled { self.state = .found(user) }
            } catch DiscoveryError.notFound {
                if !Task.isCancelled { self.state = .notFound }
            } catch let appError as AppError {
                if !Task.isCancelled {
                    self.state = .error(appError.errorDescription ?? "Erreur réseau")
                }
            } catch {
                if !Task.isCancelled {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    func clear() {
        debounceTask?.cancel()
        state = .idle
    }
}
