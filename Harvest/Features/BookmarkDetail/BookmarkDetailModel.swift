import Foundation
import Observation

@Observable
@MainActor
final class BookmarkDetailModel {

    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private let api: HarvestAPI
    private weak var listModel: BookmarkListModel?

    private(set) var bookmark: Bookmark
    private(set) var phase: Phase = .loading
    private(set) var actionInFlight = false
    private(set) var actionError: String?

    init(listItem: Bookmark, api: HarvestAPI, listModel: BookmarkListModel?) {
        self.bookmark = listItem
        self.api = api
        self.listModel = listModel
    }

    var isReady: Bool { bookmark.processingStatus == .ready }
    var cachedContent: String? { bookmark.cachedContent }

    /// Fetches the detail shape (adds `tags` + `cached_content`). Called
    /// from `.task` on the detail view so the list row's lighter shape is
    /// shown first and progressively replaced.
    func load() async {
        phase = .loading
        do {
            let detail = try await api.getBookmark(id: bookmark.id)
            bookmark = detail
            listModel?.replace(detail)
            phase = .loaded
        } catch {
            phase = .failed((error as? APIError)?.userFacingMessage ?? "Couldn't load bookmark.")
        }
    }

    func delete() async -> Bool {
        guard !actionInFlight else { return false }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }

        do {
            try await api.deleteBookmark(id: bookmark.id)
            listModel?.remove(id: bookmark.id)
            return true
        } catch {
            actionError = (error as? APIError)?.userFacingMessage ?? "Couldn't delete."
            return false
        }
    }
}
