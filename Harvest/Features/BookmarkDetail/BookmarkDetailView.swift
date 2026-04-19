import SwiftUI

struct BookmarkDetailView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let listItem: Bookmark
    let listModel: BookmarkListModel

    @State private var model: BookmarkDetailModel?
    @State private var showDeleteConfirm = false

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let model, model.phase == .loaded {
                    transitionBar(for: model)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Link("Open in browser", destination: (model?.bookmark ?? listItem).url)
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Delete this bookmark?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await model?.delete() == true { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .task {
                if model == nil {
                    model = BookmarkDetailModel(
                        listItem: listItem,
                        api: appModel.api,
                        listModel: listModel
                    )
                }
                await model?.load()
            }
    }

    @ViewBuilder private var content: some View {
        if let model {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(for: model)
                    readerBody(for: model)
                    if let error = model.actionError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func header(for model: BookmarkDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.bookmark.title ?? model.bookmark.url.absoluteString)
                .font(.title2.weight(.semibold))
            if let domain = model.bookmark.domain {
                Text(domain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let minutes = model.bookmark.readingTimeMinutes {
                Label("\(minutes) min read", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let tags = model.bookmark.tags, !tags.isEmpty {
                TagsRow(tags: tags)
            }
        }
    }

    @ViewBuilder private func readerBody(for model: BookmarkDetailModel) -> some View {
        switch (model.phase, model.cachedContent) {
        case (.loading, _):
            ProgressView().padding(.top, 32)
        case (.failed(let message), _):
            Text(message).foregroundStyle(.red)
        case (.loaded, let html?) where !html.isEmpty:
            ReaderWebView(html: html)
                .frame(minHeight: 400)
        case (.loaded, _):
            processingPlaceholder(for: model.bookmark)
        }
    }

    @ViewBuilder private func processingPlaceholder(for bookmark: Bookmark) -> some View {
        VStack(spacing: 8) {
            Image(systemName: bookmark.processingStatus == .failed ? "exclamationmark.triangle" : "hourglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(processingText(for: bookmark.processingStatus))
                .foregroundStyle(.secondary)
            Link("Open original", destination: bookmark.url)
                .font(.callout)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func processingText(for status: ProcessingStatus) -> String {
        switch status {
        case .pending, .processing: return "We're still fetching the article. Pull to refresh."
        case .failed: return "We couldn't extract this one. Open the original instead."
        case .ready: return ""
        }
    }

    // MARK: Reading-status transition bar

    @ViewBuilder private func transitionBar(for model: BookmarkDetailModel) -> some View {
        let transitions = model.bookmark.readingStatus.availableTransitions
        if transitions.isEmpty { EmptyView() } else {
            HStack(spacing: 12) {
                ForEach(transitions, id: \.target) { transition in
                    Button {
                        Task { await model.apply(transition: transition.target) }
                    } label: {
                        Label(transition.label, systemImage: icon(for: transition.target))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.actionInFlight)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }

    private func icon(for status: ReadingStatus) -> String {
        switch status {
        case .read: return "checkmark.circle"
        case .archived: return "archivebox"
        case .unread: return "arrow.uturn.backward"
        }
    }
}

private struct TagsRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}
