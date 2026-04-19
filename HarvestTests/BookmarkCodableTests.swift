import XCTest
@testable import Harvest

final class BookmarkCodableTests: XCTestCase {

    private let decoder = ISO8601JSON.makeDecoder()

    // MARK: GET /api/v1/bookmarks

    func testDecodesListResponseFromHandoffExample() throws {
        let json = """
        {
          "bookmarks": [
            {
              "id": "8b1d5234-9c1d-4fb1-8f5f-111111111111",
              "url": "https://example.com/article",
              "title": "Article Title",
              "summary": "Short excerpt…",
              "domain": "example.com",
              "processing_status": "ready",
              "reading_status": "unread",
              "reading_time_minutes": 5,
              "created_at": "2026-04-17T12:00:00Z",
              "updated_at": "2026-04-17T12:00:00Z"
            }
          ],
          "meta": { "page": 1, "per_page": 25, "total": 42 }
        }
        """.data(using: .utf8)!

        let list = try decoder.decode(BookmarkList.self, from: json)

        XCTAssertEqual(list.bookmarks.count, 1)
        XCTAssertEqual(list.bookmarks[0].title, "Article Title")
        XCTAssertEqual(list.bookmarks[0].processingStatus, .ready)
        XCTAssertEqual(list.bookmarks[0].readingStatus, .unread)
        XCTAssertEqual(list.bookmarks[0].readingTimeMinutes, 5)
        XCTAssertNil(list.bookmarks[0].tags, "list shape must not include tags")
        XCTAssertNil(list.bookmarks[0].cachedContent, "list shape must not include cached_content")
        XCTAssertEqual(list.meta.page, 1)
        XCTAssertEqual(list.meta.perPage, 25)
        XCTAssertEqual(list.meta.total, 42)
    }

    // MARK: GET /api/v1/bookmarks/:id

    func testDecodesDetailResponseWithTagsAndCachedContent() throws {
        let json = """
        {
          "id": "8b1d5234-9c1d-4fb1-8f5f-111111111111",
          "url": "https://example.com/article",
          "title": "Article Title",
          "summary": "Summary text",
          "domain": "example.com",
          "processing_status": "ready",
          "reading_status": "unread",
          "reading_time_minutes": 5,
          "created_at": "2026-04-17T12:00:00Z",
          "updated_at": "2026-04-17T12:00:00Z",
          "tags": ["ruby", "rails"],
          "cached_content": "<html>…</html>"
        }
        """.data(using: .utf8)!

        let bookmark = try decoder.decode(Bookmark.self, from: json)

        XCTAssertEqual(bookmark.tags, ["ruby", "rails"])
        XCTAssertEqual(bookmark.cachedContent, "<html>…</html>")
    }

    // MARK: POST /api/v1/bookmarks — 202

    func testDecodesPendingCreateResponseWithNullExtractedFields() throws {
        let json = """
        {
          "id": "8b1d5234-9c1d-4fb1-8f5f-111111111111",
          "url": "https://example.com/article",
          "title": null,
          "summary": null,
          "domain": "example.com",
          "processing_status": "pending",
          "reading_status": "unread",
          "reading_time_minutes": null,
          "created_at": "2026-04-17T12:00:00Z",
          "updated_at": "2026-04-17T12:00:00Z"
        }
        """.data(using: .utf8)!

        let bookmark = try decoder.decode(Bookmark.self, from: json)

        XCTAssertEqual(bookmark.processingStatus, .pending)
        XCTAssertNil(bookmark.title)
        XCTAssertNil(bookmark.summary)
        XCTAssertNil(bookmark.readingTimeMinutes)
    }

    // MARK: User envelope

    func testDecodesUserWithNullName() throws {
        let json = """
        { "id": "11111111-2222-3333-4444-555555555555",
          "email": "a@b.com", "name": null, "onboarded": false }
        """.data(using: .utf8)!

        let user = try decoder.decode(HarvestUser.self, from: json)

        XCTAssertEqual(user.email, "a@b.com")
        XCTAssertNil(user.name)
        XCTAssertFalse(user.onboarded)
    }

    // MARK: BookmarkUpdate encoding — replace semantics for tags

    func testEncodesUpdateWithTagsAtTopLevelAndStrongParamKeysNested() throws {
        let update = BookmarkUpdate(
            customTitle: "New Title",
            readingStatus: .read,
            tags: ["ruby", "rails", "web"]
        )

        let data = try ISO8601JSON.makeEncoder().encode(update)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let bookmark = try XCTUnwrap(json["bookmark"] as? [String: Any])
        XCTAssertEqual(bookmark["custom_title"] as? String, "New Title")
        XCTAssertEqual(bookmark["reading_status"] as? String, "read")
        XCTAssertEqual(json["tags"] as? [String], ["ruby", "rails", "web"])
    }

    func testOmitsTagsKeyWhenNilToLeaveServerSideSetUnchanged() throws {
        let update = BookmarkUpdate(customTitle: nil, readingStatus: .archived, tags: nil)

        let data = try ISO8601JSON.makeEncoder().encode(update)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["tags"], "omitting tags key means 'leave unchanged'; empty array would clear them")
        let bookmark = try XCTUnwrap(json["bookmark"] as? [String: Any])
        XCTAssertEqual(bookmark["reading_status"] as? String, "archived")
    }
}
