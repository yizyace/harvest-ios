import Foundation

// Tiny wrapper that wires the shared `HarvestAPI.createBookmark` to the
// keychain-backed session. The main app's full `HarvestAPI` is overkill for
// the extension (we only ever hit one endpoint), but reusing the same type
// keeps the error envelope / 202 handling / Bearer header in one place.
struct ShareAPIClient {

    private let api: HarvestAPI

    init(persistence: SessionPersistence) {
        self.api = HarvestAPI(
            baseURL: AppEnvironment.apiBaseURL,
            urlSession: .shared,
            tokenProvider: { persistence.readToken() }
        )
    }

    func createBookmark(url: URL) async throws -> Bookmark {
        try await api.createBookmark(url: url)
    }
}
