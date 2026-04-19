import Foundation

enum ProcessingStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case processing
    case ready
    case failed
}
