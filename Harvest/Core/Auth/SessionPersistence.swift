import Foundation

// Abstracts keychain access so tests can swap in an in-memory store. The real
// implementation lives in `KeychainSessionPersistence`; tests use the
// in-memory stub below to avoid needing entitlements.
protocol SessionPersistence: Sendable {
    func readToken() -> String?
    func writeToken(_ token: String?)
    func readUser() -> HarvestUser?
    func writeUser(_ user: HarvestUser?)
}

final class InMemorySessionPersistence: SessionPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var user: HarvestUser?

    init(token: String? = nil, user: HarvestUser? = nil) {
        self.token = token
        self.user = user
    }

    func readToken() -> String? { lock.withLock { token } }
    func writeToken(_ token: String?) { lock.withLock { self.token = token } }
    func readUser() -> HarvestUser? { lock.withLock { user } }
    func writeUser(_ user: HarvestUser?) { lock.withLock { self.user = user } }
}
