import XCTest
@testable import Harvest

final class HarvestAPITests: XCTestCase {

    private let base = URL(string: "https://harvest.bitrat.io")!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeAPI(token: String? = "test-token") -> HarvestAPI {
        HarvestAPI(
            baseURL: base,
            urlSession: URLProtocolStub.session(),
            tokenProvider: { token }
        )
    }

    // MARK: POST /auth/magic_link

    func testSendMagicLinkPostsEmailAndAcceptsMessageResponse() async throws {
        URLProtocolStub.enqueue(
            .init(statusCode: 200, body: #"{"message":"Magic link sent"}"#.data(using: .utf8)!),
            for: Endpoint.magicLink(base: base)
        )

        try await makeAPI().sendMagicLink(email: "user@example.com")

        let recorded = try XCTUnwrap(URLProtocolStub.allRecorded.first)
        XCTAssertEqual(recorded.method, "POST")
        XCTAssertEqual(recorded.headers["Content-Type"], "application/json")
        XCTAssertEqual(recorded.headers["Accept"], "application/json")
        let body = try XCTUnwrap(recorded.body).map { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(body, #"{"email":"user@example.com"}"#)
    }

    // MARK: GET /auth/verify — Accept: application/json is load-bearing

    func testVerifySendsAcceptJSONHeaderAndParsesSessionToken() async throws {
        let url = Endpoint.verify(base: base, token: "magic-abc")
        URLProtocolStub.enqueue(
            .init(
                statusCode: 200,
                body: #"""
                {
                  "authenticated": true,
                  "user": {"id":"11111111-2222-3333-4444-555555555555","email":"a@b.com","name":null,"onboarded":false},
                  "session_token": "sess-xyz"
                }
                """#.data(using: .utf8)!
            ),
            for: url
        )

        let response = try await makeAPI(token: nil).verify(token: "magic-abc")

        XCTAssertEqual(response.sessionToken, "sess-xyz")
        XCTAssertEqual(response.user.email, "a@b.com")

        let recorded = try XCTUnwrap(URLProtocolStub.allRecorded.first)
        XCTAssertEqual(recorded.headers["Accept"], "application/json",
                       "handoff §4: without Accept the server returns HTML")
    }

    func testVerifyRaisesUnauthorizedOn401() async {
        URLProtocolStub.enqueue(
            .init(statusCode: 401, body: #"{"error":"Invalid or expired link"}"#.data(using: .utf8)!),
            for: Endpoint.verify(base: base, token: "bad")
        )

        do {
            _ = try await makeAPI(token: nil).verify(token: "bad")
            XCTFail("expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: GET /api/v1/bookmarks — bearer token

    func testListBookmarksAttachesBearerTokenAndParsesResponse() async throws {
        let url = Endpoint.bookmarksList(base: base, filters: .none, limit: 25)
        URLProtocolStub.enqueue(
            .init(
                statusCode: 200,
                body: #"""
                {
                  "bookmarks": [],
                  "meta": {"limit":25,"next_cursor":null,"has_more":false}
                }
                """#.data(using: .utf8)!
            ),
            for: url
        )

        let list = try await makeAPI().listBookmarks()

        XCTAssertEqual(list.meta.limit, 25)
        XCTAssertFalse(list.meta.hasMore)
        XCTAssertNil(list.meta.nextCursor)

        let recorded = try XCTUnwrap(URLProtocolStub.allRecorded.first)
        XCTAssertEqual(recorded.headers["Authorization"], "Bearer test-token")
    }

    func testListFiltersAndCursorSerializeAsQueryParams() async throws {
        let filters = BookmarkFilters(
            processingStatus: .ready,
            readingStatus: .unread,
            tag: "ruby"
        )
        let url = Endpoint.bookmarksList(base: base, filters: filters, limit: 50, after: "cursor-123")
        URLProtocolStub.enqueue(
            .init(
                statusCode: 200,
                body: #"{"bookmarks":[],"meta":{"limit":50,"next_cursor":null,"has_more":false}}"#.data(using: .utf8)!
            ),
            for: url
        )

        _ = try await makeAPI().listBookmarks(filters: filters, limit: 50, after: "cursor-123")

        let recorded = try XCTUnwrap(URLProtocolStub.allRecorded.first)
        let query = URLComponents(url: recorded.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["processing_status"], "ready")
        XCTAssertEqual(dict["reading_status"], "unread")
        XCTAssertEqual(dict["tag"], "ruby")
        XCTAssertEqual(dict["limit"], "50")
        XCTAssertEqual(dict["after"], "cursor-123")
        XCTAssertNil(dict["before"])
    }

    func testListMapsInvalidCursorToTypedError() async {
        let url = Endpoint.bookmarksList(base: base, filters: .none, limit: 25, after: "stale")
        URLProtocolStub.enqueue(
            .init(statusCode: 400, body: #"{"error":"Invalid cursor"}"#.data(using: .utf8)!),
            for: url
        )

        do {
            _ = try await makeAPI().listBookmarks(after: "stale")
            XCTFail("expected invalidCursor")
        } catch let error as APIError {
            XCTAssertEqual(error, .invalidCursor)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: POST /api/v1/bookmarks — 202 Accepted

    func testCreateBookmarkTreats202AsSuccess() async throws {
        URLProtocolStub.enqueue(
            .init(
                statusCode: 202,
                body: #"""
                {
                  "id": "11111111-2222-3333-4444-555555555555",
                  "url": "https://example.com",
                  "title": null,
                  "summary": null,
                  "domain": "example.com",
                  "processing_status": "pending",
                  "reading_status": "unread",
                  "reading_time_minutes": null,
                  "created_at": "2026-04-17T12:00:00Z",
                  "updated_at": "2026-04-17T12:00:00Z"
                }
                """#.data(using: .utf8)!
            ),
            for: Endpoint.bookmarks(base: base)
        )

        let bookmark = try await makeAPI().createBookmark(url: URL(string: "https://example.com")!)

        XCTAssertEqual(bookmark.processingStatus, .pending)
        XCTAssertEqual(bookmark.readingStatus, .unread)
    }

    func testCreateBookmarkSurfacesDuplicateValidationError() async {
        URLProtocolStub.enqueue(
            .init(
                statusCode: 422,
                body: #"""
                {"errors":[{"field":"page_id","message":"has already been taken"}]}
                """#.data(using: .utf8)!
            ),
            for: Endpoint.bookmarks(base: base)
        )

        do {
            _ = try await makeAPI().createBookmark(url: URL(string: "https://example.com")!)
            XCTFail("expected validation error")
        } catch let error as APIError {
            XCTAssertEqual(
                error,
                .validation([FieldError(field: "page_id", message: "has already been taken")])
            )
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: PATCH — 422 invalid transition

    func testUpdateBookmarkSurfacesInvalidTransitionAs422() async {
        let id = UUID()
        URLProtocolStub.enqueue(
            .init(
                statusCode: 422,
                body: #"""
                {"errors":[{"field":"reading_status","message":"cannot transition to 'unread' from 'read'"}]}
                """#.data(using: .utf8)!
            ),
            for: Endpoint.bookmark(base: base, id: id)
        )

        do {
            _ = try await makeAPI().updateBookmark(
                id: id,
                update: BookmarkUpdate(readingStatus: .unread)
            )
            XCTFail("expected 422")
        } catch let error as APIError {
            guard case .validation(let errors) = error else {
                XCTFail("expected validation, got \(error)"); return
            }
            XCTAssertEqual(errors.first?.field, "reading_status")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: DELETE — 204 empty body

    func testDeleteBookmarkTolerates204EmptyBody() async throws {
        let id = UUID()
        URLProtocolStub.enqueue(
            .init(statusCode: 204, body: Data()),
            for: Endpoint.bookmark(base: base, id: id)
        )

        try await makeAPI().deleteBookmark(id: id)

        let recorded = try XCTUnwrap(URLProtocolStub.allRecorded.first)
        XCTAssertEqual(recorded.method, "DELETE")
    }

    func testDeleteBookmarkRaisesNotFoundOn404() async {
        let id = UUID()
        URLProtocolStub.enqueue(
            .init(statusCode: 404, body: #"{"error":"Not found"}"#.data(using: .utf8)!),
            for: Endpoint.bookmark(base: base, id: id)
        )

        do {
            try await makeAPI().deleteBookmark(id: id)
            XCTFail("expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound("Not found"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: 401 on any API endpoint

    func testListReturns401AsUnauthorizedSoAppModelCanSignOut() async {
        URLProtocolStub.enqueue(
            .init(statusCode: 401, body: #"{"error":"Not authenticated"}"#.data(using: .utf8)!),
            for: Endpoint.bookmarksList(base: base, filters: .none, limit: 25)
        )

        do {
            _ = try await makeAPI().listBookmarks()
            XCTFail("expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
