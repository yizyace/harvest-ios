import Foundation

struct PaginationMeta: Codable, Equatable, Sendable {
    let page: Int
    let perPage: Int
    let total: Int
}

struct BookmarkList: Codable, Equatable, Sendable {
    let bookmarks: [Bookmark]
    let meta: PaginationMeta
}
