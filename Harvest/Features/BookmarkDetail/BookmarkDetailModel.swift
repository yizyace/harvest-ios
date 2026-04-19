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

    // MARK: Reading-status transitions

    func apply(transition target: ReadingStatus) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }

        // TODO(learning-mode): optimistic vs. pessimistic. Current
        // implementation is *pessimistic* — waits for the server to confirm
        // before mutating `bookmark`. The alternative is to mutate locally
        // first and roll back on 422. The handoff pins the 422 rules so
        // optimistic is tractable, but the latency on a good connection is
        // small enough that pessimistic may feel fine. Revisit once the UI
        // is wired and we can feel the delay.
        do {
            let updated = try await api.updateBookmark(
                id: bookmark.id,
                update: BookmarkUpdate(readingStatus: target)
            )
            bookmark = updated
            listModel?.replace(updated)
        } catch {
            actionError = (error as? APIError)?.userFacingMessage ?? "Couldn't update status."
        }
    }

    // MARK: Tags + custom title

    func applyEdits(customTitle: String?, tags: [String]?) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }

        do {
            let updated = try await api.updateBookmark(
                id: bookmark.id,
                update: BookmarkUpdate(customTitle: customTitle, tags: tags)
            )
            bookmark = updated
            listModel?.replace(updated)
        } catch {
            actionError = (error as? APIError)?.userFacingMessage ?? "Couldn't save edits."
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
