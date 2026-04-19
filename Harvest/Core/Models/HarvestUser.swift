import Foundation

struct HarvestUser: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let email: String
    let name: String?
    let onboarded: Bool
}
