import Foundation

struct MagicLinkResponse: Decodable { let message: String }

struct VerifyResponse: Decodable {
    let authenticated: Bool
    let user: HarvestUser
    let sessionToken: String
}

struct SessionCheck: Decodable {
    let authenticated: Bool
    let user: HarvestUser?
}

// All HTTP for the Harvest API. Constructed once at app launch with a
// token-provider closure so it can observe session changes without needing a
// rebuild — the closure is re-evaluated on every request.
struct HarvestAPI: Sendable {

    let baseURL: URL
    let urlSession: URLSession
    let tokenProvider: @Sendable () -> String?

    private var decoder: JSONDecoder { ISO8601JSON.makeDecoder() }
    private var encoder: JSONEncoder { ISO8601JSON.makeEncoder() }

    // MARK: Auth

    func sendMagicLink(email: String) async throws {
        let body = ["email": email]
        _ = try await perform(
            request: makeRequest(
                url: Endpoint.magicLink(base: baseURL),
                method: "POST",
                jsonBody: body,
                authenticated: false
            ),
            decodeAs: MagicLinkResponse.self
        )
    }

    /// Calls `GET /auth/verify?token=…` with `Accept: application/json`. The
    /// Accept header is load-bearing — without it the server returns HTML
    /// (handoff §4 — the Chrome extension flow piggybacks on that).
    func verify(token: String) async throws -> VerifyResponse {
        var request = URLRequest(url: Endpoint.verify(base: baseURL, token: token))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request: request, decodeAs: VerifyResponse.self)
    }

    func fetchSession() async throws -> SessionCheck {
        try await perform(
            request: makeRequest(
                url: Endpoint.session(base: baseURL),
                method: "GET",
                jsonBody: Optional<String>.none,
                authenticated: true
            ),
            decodeAs: SessionCheck.self
        )
    }

    func signOut() async throws {
        _ = try await perform(
            request: makeRequest(
                url: Endpoint.signOut(base: baseURL),
                method: "DELETE",
                jsonBody: Optional<String>.none,
                authenticated: true
            ),
            decodeAs: EmptyObject.self
        )
    }

    /// Deletes the signed-in user + all their bookmarks/sessions/tags
    /// server-side. Returns 204 with an empty body; the bearer token is
    /// invalidated along with the session, so subsequent authenticated
    /// calls will 401. Callers should treat 401 here as success — the
    /// token was already dead from a prior attempt.
    func deleteAccount() async throws {
        let (data, response) = try await fetch(
            request: makeRequest(
                url: Endpoint.currentUser(base: baseURL),
                method: "DELETE",
                jsonBody: Optional<String>.none,
                authenticated: true
            )
        )
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Expected HTTPURLResponse on DELETE")
        }
        if http.statusCode == 204 { return }
        throw APIError.from(statusCode: http.statusCode, data: data)
    }

    // MARK: Bookmarks

    func listBookmarks(
        filters: BookmarkFilters = .none,
        limit: Int = 25,
        after: String? = nil,
        before: String? = nil
    ) async throws -> BookmarkList {
        try await perform(
            request: makeRequest(
                url: Endpoint.bookmarksList(base: baseURL, filters: filters, limit: limit, after: after, before: before),
                method: "GET",
                jsonBody: Optional<String>.none,
                authenticated: true
            ),
            decodeAs: BookmarkList.self
        )
    }

    func getBookmark(id: UUID) async throws -> Bookmark {
        try await perform(
            request: makeRequest(
                url: Endpoint.bookmark(base: baseURL, id: id),
                method: "GET",
                jsonBody: Optional<String>.none,
                authenticated: true
            ),
            decodeAs: Bookmark.self
        )
    }

    /// Returns 202 with the freshly-created bookmark in `pending` state. The
    /// server does fetch + extraction asynchronously — poll by re-fetching
    /// the detail to see `processing_status` transition to `ready`.
    func createBookmark(
        url: URL,
        extracted: ExtractedContent? = nil,
        html: String? = nil
    ) async throws -> Bookmark {
        let body = CreateBookmarkBody(
            bookmark: .init(
                url: url.absoluteString,
                extracted: extracted,
                html: (html?.isEmpty == false) ? html : nil
            )
        )
        return try await perform(
            request: makeRequest(
                url: Endpoint.bookmarks(base: baseURL),
                method: "POST",
                jsonBody: body,
                authenticated: true
            ),
            decodeAs: Bookmark.self
        )
    }

    private struct CreateBookmarkBody: Encodable {
        let bookmark: Inner

        struct Inner: Encodable {
            let url: String
            let extracted: ExtractedContent?
            let html: String?

            private enum CodingKeys: String, CodingKey { case url, extracted, html }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(url, forKey: .url)
                try container.encodeIfPresent(extracted, forKey: .extracted)
                try container.encodeIfPresent(html, forKey: .html)
            }
        }
    }

    func updateBookmark(id: UUID, update: BookmarkUpdate) async throws -> Bookmark {
        try await perform(
            request: makeRequest(
                url: Endpoint.bookmark(base: baseURL, id: id),
                method: "PATCH",
                jsonBody: update,
                authenticated: true
            ),
            decodeAs: Bookmark.self
        )
    }

    func deleteBookmark(id: UUID) async throws {
        let (data, response) = try await fetch(
            request: makeRequest(
                url: Endpoint.bookmark(base: baseURL, id: id),
                method: "DELETE",
                jsonBody: Optional<String>.none,
                authenticated: true
            )
        )
        // DELETE returns 204 with empty body — don't try to decode.
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Expected HTTPURLResponse on DELETE")
        }
        if http.statusCode == 204 { return }
        throw APIError.from(statusCode: http.statusCode, data: data)
    }

    // MARK: - Request construction

    private func makeRequest<Body: Encodable>(
        url: URL,
        method: String,
        jsonBody: Body?,
        authenticated: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(jsonBody)
        }

        if authenticated, let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Dispatch + envelope handling

    private func perform<T: Decodable>(request: URLRequest, decodeAs: T.Type) async throws -> T {
        let (data, response) = try await fetch(request: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("Expected HTTPURLResponse")
        }

        // 200 and 202 are both success shapes: `POST /api/v1/bookmarks`
        // returns 202, every other success returns 200. Allow both.
        guard (200...299).contains(http.statusCode) else {
            throw APIError.from(statusCode: http.statusCode, data: data)
        }

        // Empty-body 200/204 callers should handle decoding themselves; this
        // path only runs when a body is expected. EmptyObject lets the
        // signOut call share the generic path without raising.
        if T.self == EmptyObject.self, data.isEmpty {
            return EmptyObject() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func fetch(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let urlError as URLError {
            throw APIError.transport(urlError)
        }
    }
}

struct EmptyObject: Decodable, Sendable {}
