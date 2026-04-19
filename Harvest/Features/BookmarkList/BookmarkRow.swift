import SwiftUI

struct BookmarkRow: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bookmark.title ?? bookmark.url.absoluteString)
                .font(.headline)
                .lineLimit(2)

            if let summary = bookmark.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let domain = bookmark.domain {
                    Label(domain, systemImage: "link")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let minutes = bookmark.readingTimeMinutes {
                    Label("\(minutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusBadge: some View {
        switch bookmark.processingStatus {
        case .pending, .processing:
            Label("Processing", systemImage: "hourglass")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.red)
        case .ready:
            EmptyView()
        }
    }
}
