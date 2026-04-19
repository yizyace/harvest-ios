import SwiftUI

struct BookmarkListView: View {

    @Environment(AppModel.self) private var appModel
    @State private var model: BookmarkListModel?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Harvest")
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            filterMenu
                            Divider()
                            Button("Sign out", role: .destructive) {
                                Task { await appModel.signOut() }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .task { await ensureModel().refresh() }
        }
    }

    @ViewBuilder private var content: some View {
        if let model {
            listBody(model: model)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func listBody(model: BookmarkListModel) -> some View {
        List {
            if let filter = model.readingStatusFilter {
                Section {
                    Label("Filter: \(filter.rawValue.capitalized)", systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(model.bookmarks) { bookmark in
                NavigationLink(value: bookmark.id) {
                    BookmarkRow(bookmark: bookmark)
                }
                .task { await model.loadMoreIfNeeded(currentItem: bookmark) }
            }

            switch model.phase {
            case .loadingMore:
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            case .idle where model.bookmarks.isEmpty:
                ContentUnavailableView(
                    "No bookmarks yet",
                    systemImage: "bookmark",
                    description: Text("Save a URL from Safari's share sheet to see it here.")
                )
                .listRowSeparator(.hidden)
            default:
                EmptyView()
            }
        }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder private var filterMenu: some View {
        Button { setFilter(nil) } label: {
            Label("All", systemImage: readingFilter == nil ? "checkmark" : "")
        }
        Button { setFilter(.unread) } label: {
            Label("Unread", systemImage: readingFilter == .unread ? "checkmark" : "")
        }
        Button { setFilter(.read) } label: {
            Label("Read", systemImage: readingFilter == .read ? "checkmark" : "")
        }
        Button { setFilter(.archived) } label: {
            Label("Archived", systemImage: readingFilter == .archived ? "checkmark" : "")
        }
    }

    private var readingFilter: ReadingStatus? { model?.readingStatusFilter }

    private func setFilter(_ filter: ReadingStatus?) {
        ensureModel().readingStatusFilter = filter
    }

    @discardableResult
    private func ensureModel() -> BookmarkListModel {
        if let model { return model }
        let created = BookmarkListModel(api: appModel.api)
        model = created
        return created
    }
}
