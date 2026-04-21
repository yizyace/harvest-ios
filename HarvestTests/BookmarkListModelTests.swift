import XCTest
@testable import Harvest

@MainActor
final class BookmarkListModelTests: XCTestCase {

    private let base = URL(string: "https://harvest.bitrat.io")!

    override func setUp() {
        super.setUp()
        URLProtocolStub.reset()
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeAPI() -> HarvestAPI {
        HarvestAPI(
            baseURL: base,
            urlSession: URLProtocolStub.session(),
            tokenProvider: { "test-token" }
        )
    }

    private func stubList(after: String? = nil, body: String) {
        let url = Endpoint.bookmarksList(base: base, filters: .none, limit: 25, after: after)
        URLProtocolStub.enqueue(
            .init(statusCode: 200, body: body.data(using: .utf8)!),
            for: url
        )
    }

    private func stubInvalidCursor(after: String) {
        let url = Endpoint.bookmarksList(base: base, filters: .none, limit: 25, after: after)
        URLProtocolStub.enqueue(
            .init(statusCode: 400, body: #"{"error":"Invalid cursor"}"#.data(using: .utf8)!),
            for: url
        )
    }

    private func bookmarkJSON(id: String, title: String, createdAt: String = "2026-04-18T12:00:00Z") -> String {
        """
        {
          "id": "\(id)",
          "url": "https://example.com/\(id)",
          "title": "\(title)",
          "summary": null,
          "domain": "example.com",
          "processing_status": "ready",
          "reading_status": "unread",
          "reading_time_minutes": 5,
          "created_at": "\(createdAt)",
          "updated_at": "\(createdAt)"
        }
        """
    }

    // MARK: refresh() — initial load

    func testRefreshLoadsFirstPageAndStoresCursor() async {
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A"))],
          "meta": {"limit":25,"next_cursor":"cursor-1","has_more":true}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()

        XCTAssertEqual(model.bookmarks.count, 1)
        XCTAssertEqual(model.bookmarks[0].title, "A")
        XCTAssertEqual(model.nextCursor, "cursor-1")
        XCTAssertTrue(model.hasMore)
        XCTAssertEqual(model.phase, .idle)
    }

    // MARK: loadMore() — cursor handoff

    func testLoadMoreSendsAfterCursorAndAppendsUniqueItems() async {
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A"))],
          "meta": {"limit":25,"next_cursor":"cursor-1","has_more":true}
        }
        """)
        stubList(after: "cursor-1", body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "22222222-2222-3333-4444-555555555555", title: "B"))],
          "meta": {"limit":25,"next_cursor":null,"has_more":false}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()
        await model.loadMore()

        XCTAssertEqual(model.bookmarks.map(\.title), ["A", "B"])
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.nextCursor)
    }

    func testLoadMoreDedupesOverlappingIds() async {
        let sharedId = "11111111-2222-3333-4444-555555555555"
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: sharedId, title: "A"))],
          "meta": {"limit":25,"next_cursor":"cursor-1","has_more":true}
        }
        """)
        stubList(after: "cursor-1", body: """
        {
          "bookmarks": [
            \(bookmarkJSON(id: sharedId, title: "A-dup")),
            \(bookmarkJSON(id: "22222222-2222-3333-4444-555555555555", title: "B"))
          ],
          "meta": {"limit":25,"next_cursor":null,"has_more":false}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()
        await model.loadMore()

        XCTAssertEqual(model.bookmarks.count, 2, "overlapping id must not appear twice")
        XCTAssertEqual(model.bookmarks.map(\.title), ["A", "B"], "local copy wins on loadMore dedupe")
    }

    // MARK: refresh() — merge-dedupe after pagination

    func testRefreshPreservesItemsPastFirstPageAndPrependsNewOnes() async {
        // Initial: one item, more available.
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A", createdAt: "2026-04-18T12:00:00Z"))],
          "meta": {"limit":25,"next_cursor":"cursor-1","has_more":true}
        }
        """)
        // Page 2: older item.
        stubList(after: "cursor-1", body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "22222222-2222-3333-4444-555555555555", title: "B", createdAt: "2026-04-17T12:00:00Z"))],
          "meta": {"limit":25,"next_cursor":null,"has_more":false}
        }
        """)
        // Refresh after load-more: a new item appeared at the top; A still
        // on page 1; B is older than page-1 scope so it's not in this response.
        stubList(body: """
        {
          "bookmarks": [
            \(bookmarkJSON(id: "33333333-2222-3333-4444-555555555555", title: "NEW", createdAt: "2026-04-19T12:00:00Z")),
            \(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A", createdAt: "2026-04-18T12:00:00Z"))
          ],
          "meta": {"limit":25,"next_cursor":"cursor-2","has_more":true}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.bookmarks.map(\.title), ["A", "B"])

        await model.refresh()

        XCTAssertEqual(
            model.bookmarks.map(\.title),
            ["NEW", "A", "B"],
            "refresh must prepend new items and preserve items past page 1"
        )
        XCTAssertEqual(model.nextCursor, "cursor-2")
    }

    // MARK: Filter change — reset

    func testFilterChangeResetsTheList() async {
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A"))],
          "meta": {"limit":25,"next_cursor":null,"has_more":false}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()
        XCTAssertEqual(model.bookmarks.count, 1)

        // Stub the filtered request — different URL, different response.
        let filteredURL = Endpoint.bookmarksList(
            base: base,
            filters: BookmarkFilters(readingStatus: .unread),
            limit: 25
        )
        URLProtocolStub.enqueue(
            .init(
                statusCode: 200,
                body: #"{"bookmarks":[],"meta":{"limit":25,"next_cursor":null,"has_more":false}}"#.data(using: .utf8)!
            ),
            for: filteredURL
        )

        model.readingStatusFilter = .unread
        // didSet fires Task { reset() } — give it a chance to run.
        await Task.yield()
        // Poll briefly; the async reset completes on the next main-actor hop.
        for _ in 0..<10 where !model.bookmarks.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(model.bookmarks.isEmpty, "filter change must reset the list")
    }

    // MARK: loadMore() — stale cursor recovery

    func testLoadMoreOnInvalidCursorFallsBackToRefresh() async {
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "11111111-2222-3333-4444-555555555555", title: "A"))],
          "meta": {"limit":25,"next_cursor":"stale","has_more":true}
        }
        """)
        stubInvalidCursor(after: "stale")
        // Refresh fallback fetches page 1 again — stub a fresh response.
        stubList(body: """
        {
          "bookmarks": [\(bookmarkJSON(id: "33333333-2222-3333-4444-555555555555", title: "FRESH"))],
          "meta": {"limit":25,"next_cursor":null,"has_more":false}
        }
        """)

        let model = BookmarkListModel(api: makeAPI())
        await model.refresh()
        await model.loadMore()

        // Stale-cursor recovery delegates to refresh(), which merge-dedupes:
        // "A" wasn't in the refresh response (server only returned "FRESH"),
        // so it's preserved in place. This keeps the user's scroll context
        // instead of yanking them back to the top on a transient error.
        XCTAssertEqual(model.bookmarks.map(\.title), ["FRESH", "A"])
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.phase, .idle)
    }
}
