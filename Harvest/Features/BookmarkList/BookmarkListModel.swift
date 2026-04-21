import Foundation
import Observation

@Observable
@MainActor
final class BookmarkListModel {

    enum Phase: Equatable {
        case idle
        case loading
        case loadingMore
        case failed(String)
    }

    private let api: HarvestAPI
    private let limit = 25

    private(set) var bookmarks: [Bookmark] = []
    private(set) var phase: Phase = .idle
    private(set) var nextCursor: String? = nil
    private(set) var hasMore: Bool = false

    var readingStatusFilter: ReadingStatus? {
        didSet {
            guard oldValue != readingStatusFilter else { return }
            Task { await reset() }
        }
    }

    init(api: HarvestAPI) {
        self.api = api
    }

    var filters: BookmarkFilters {
        BookmarkFilters(readingStatus: readingStatusFilter)
    }

    /// Pull-to-refresh: re-fetch the first page and merge-dedupe with the
    /// local list. Items past the refresh response (pages 2+ the user
    /// already scrolled to) are preserved in place.
    ///
    /// Per handoff §Pagination flows, cursors are opaque — we can't ask the
    /// server for "everything newer than X" without a `first_cursor` we
    /// don't have. So we re-fetch page 1 and reconcile client-side.
    func refresh() async {
        phase = .loading
        do {
            let list = try await api.listBookmarks(filters: filters, limit: limit)
            bookmarks = mergeRefreshed(list.bookmarks, into: bookmarks)
            nextCursor = list.meta.nextCursor
            hasMore = list.meta.hasMore
            phase = .idle
        } catch APIError.invalidCursor {
            // No cursor sent — shouldn't happen, but keep state coherent.
            nextCursor = nil
            hasMore = false
            phase = .idle
        } catch {
            phase = .failed((error as? APIError)?.userFacingMessage ?? "Couldn't load bookmarks.")
        }
    }

    /// Clears local state and reloads from the top. Called on filter change —
    /// when the query space changes, the old list is meaningless.
    func reset() async {
        bookmarks = []
        nextCursor = nil
        hasMore = false
        await refresh()
    }

    func loadMoreIfNeeded(currentItem: Bookmark) async {
        // Trigger a page fetch when the user scrolls within ~5 rows of the
        // end of the list. Guard against parallel loads via phase.
        guard phase == .idle, hasMore else { return }
        guard let index = bookmarks.firstIndex(where: { $0.id == currentItem.id }) else { return }
        let threshold = max(0, bookmarks.count - 5)
        guard index >= threshold else { return }
        await loadMore()
    }

    func loadMore() async {
        guard phase != .loadingMore, hasMore, let cursor = nextCursor else { return }
        phase = .loadingMore
        do {
            let list = try await api.listBookmarks(filters: filters, limit: limit, after: cursor)
            // Dedupe by id — a new bookmark created between pages could
            // otherwise appear twice as the list scrolls. Keep local copies
            // on collision (cheap; loadMore isn't about refreshing stale data).
            let existing = Set(bookmarks.map(\.id))
            let fresh = list.bookmarks.filter { !existing.contains($0.id) }
            bookmarks.append(contentsOf: fresh)
            nextCursor = list.meta.nextCursor
            hasMore = list.meta.hasMore
            phase = .idle
        } catch APIError.invalidCursor {
            // Stale or malformed cursor — fall back to a full refresh from
            // the top. Silent recovery; the user sees "loading more" briefly
            // followed by fresh data.
            nextCursor = nil
            hasMore = false
            await refresh()
        } catch {
            phase = .failed((error as? APIError)?.userFacingMessage ?? "Couldn't load more.")
        }
    }

    func replace(_ updated: Bookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == updated.id }) {
            bookmarks[index] = updated
        }
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    // Items past page 1 (loaded via loadMore) aren't in the refresh response
    // — preserve them in place. Server version wins on id collision so edits
    // from another client (web, extension) propagate into the list.
    private func mergeRefreshed(_ refreshed: [Bookmark], into current: [Bookmark]) -> [Bookmark] {
        let refreshedIds = Set(refreshed.map(\.id))
        let kept = current.filter { !refreshedIds.contains($0.id) }
        return refreshed + kept
    }
}
