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
    private let perPage = 25

    private(set) var bookmarks: [Bookmark] = []
    private(set) var phase: Phase = .idle
    private(set) var currentPage = 0
    private(set) var totalCount = 0

    var readingStatusFilter: ReadingStatus? {
        didSet {
            guard oldValue != readingStatusFilter else { return }
            Task { await refresh() }
        }
    }

    init(api: HarvestAPI) {
        self.api = api
    }

    var hasMore: Bool { bookmarks.count < totalCount }

    var filters: BookmarkFilters {
        BookmarkFilters(readingStatus: readingStatusFilter)
    }

    func refresh() async {
        phase = .loading
        do {
            let list = try await api.listBookmarks(filters: filters, page: 1, perPage: perPage)
            bookmarks = list.bookmarks
            currentPage = list.meta.page
            totalCount = list.meta.total
            phase = .idle
        } catch {
            phase = .failed((error as? APIError)?.userFacingMessage ?? "Couldn't load bookmarks.")
        }
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
        guard hasMore else { return }
        phase = .loadingMore
        do {
            let list = try await api.listBookmarks(
                filters: filters,
                page: currentPage + 1,
                perPage: perPage
            )
            // Dedupe by id — the server is ordered by created_at DESC, so a
            // new bookmark created between pages could otherwise appear
            // twice as the list scrolls.
            let existing = Set(bookmarks.map(\.id))
            let fresh = list.bookmarks.filter { !existing.contains($0.id) }
            bookmarks.append(contentsOf: fresh)
            currentPage = list.meta.page
            totalCount = list.meta.total
            phase = .idle
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
        totalCount = max(0, totalCount - 1)
    }
}
