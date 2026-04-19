import Foundation

struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let title: String?
    let summary: String?
    let domain: String?
    let processingStatus: ProcessingStatus
    let readingStatus: ReadingStatus
    let readingTimeMinutes: Int?
    let createdAt: Date
    let updatedAt: Date
    // Detail-only fields — nil in list responses.
    let tags: [String]?
    let cachedContent: String?
}

// PATCH /api/v1/bookmarks/:id payload helpers. The server accepts only
// `custom_title` and `reading_status` inside the `bookmark` object; `tags`
// sits at the top level and *replaces* the set.
struct BookmarkUpdate: Encodable, Equatable, Sendable {
    var customTitle: String?
    var readingStatus: ReadingStatus?
    var tags: [String]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: RootKey.self)

        if customTitle != nil || readingStatus != nil {
            var nested = container.nestedContainer(keyedBy: BookmarkKey.self, forKey: .bookmark)
            if let customTitle { try nested.encode(customTitle, forKey: .customTitle) }
            if let readingStatus { try nested.encode(readingStatus, forKey: .readingStatus) }
        }

        // Omit the `tags` key entirely when nil — server treats missing as
        // "leave tags unchanged" (vs. an empty array which clears them).
        if let tags { try container.encode(tags, forKey: .tags) }
    }

    private enum RootKey: String, CodingKey { case bookmark, tags }
    private enum BookmarkKey: String, CodingKey {
        case customTitle = "custom_title"
        case readingStatus = "reading_status"
    }
}
