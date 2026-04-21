import Foundation

struct PaginationMeta: Codable, Equatable, Sendable {
    let limit: Int
    let nextCursor: String?
    let hasMore: Bool
}

struct BookmarkList: Codable, Equatable, Sendable {
    let bookmarks: [Bookmark]
    let meta: PaginationMeta
}
