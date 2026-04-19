import Foundation

enum ReadingStatus: String, Codable, CaseIterable, Sendable {
    case unread
    case read
    case archived
}

// The transitions the *client* offers. These match the server's allowed
// transitions from handoff §5 minus the `archived → "unread"` quirk, which
// silently becomes `read` server-side. We model the unarchive button
// explicitly so the UI stays honest about what the server will do.
struct ReadingStatusTransition: Equatable, Sendable {
    let label: String
    let target: ReadingStatus
}

extension ReadingStatus {
    var availableTransitions: [ReadingStatusTransition] {
        switch self {
        case .unread:
            return [
                ReadingStatusTransition(label: "Mark read", target: .read),
                ReadingStatusTransition(label: "Archive", target: .archived)
            ]
        case .read:
            return [
                ReadingStatusTransition(label: "Archive", target: .archived)
            ]
        case .archived:
            return [
                ReadingStatusTransition(label: "Unarchive", target: .read)
            ]
        }
    }
}
