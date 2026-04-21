import Foundation

struct BookmarkFilters: Equatable, Sendable {
    var processingStatus: ProcessingStatus?
    var readingStatus: ReadingStatus?
    var tag: String?

    static let none = BookmarkFilters()
}

// URL builders — one per endpoint. Isolated here so the API client stays
// focused on transport + envelope handling.
enum Endpoint {
    static func magicLink(base: URL) -> URL {
        base.appendingPathComponent("auth/magic_link")
    }

    static func verify(base: URL, token: String) -> URL {
        var components = URLComponents(url: base.appendingPathComponent("auth/verify"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    static func session(base: URL) -> URL {
        base.appendingPathComponent("auth/session")
    }

    static func signOut(base: URL) -> URL {
        base.appendingPathComponent("auth/sign_out")
    }

    static func bookmarks(base: URL) -> URL {
        base.appendingPathComponent("api/v1/bookmarks")
    }

    static func bookmark(base: URL, id: UUID) -> URL {
        base.appendingPathComponent("api/v1/bookmarks/\(id.uuidString.lowercased())")
    }

    static func bookmarksList(
        base: URL,
        filters: BookmarkFilters,
        limit: Int,
        after: String? = nil,
        before: String? = nil
    ) -> URL {
        var components = URLComponents(url: bookmarks(base: base), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let after { items.append(URLQueryItem(name: "after", value: after)) }
        if let before { items.append(URLQueryItem(name: "before", value: before)) }
        if let status = filters.processingStatus {
            items.append(URLQueryItem(name: "processing_status", value: status.rawValue))
        }
        if let status = filters.readingStatus {
            items.append(URLQueryItem(name: "reading_status", value: status.rawValue))
        }
        if let tag = filters.tag {
            items.append(URLQueryItem(name: "tag", value: tag))
        }
        components.queryItems = items
        return components.url!
    }
}
