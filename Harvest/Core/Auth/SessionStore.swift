import Foundation
import Observation

// Tracks the current bearer token + signed-in user. Views observe this via
// `AppModel`. On 401 from an API call, `AppModel` calls `clear()` and the
// root switch flips back to `SignInView`.
@Observable
final class SessionStore {

    private let persistence: SessionPersistence

    private(set) var token: String?
    private(set) var user: HarvestUser?

    init(persistence: SessionPersistence) {
        self.persistence = persistence
        self.token = persistence.readToken()
        self.user = persistence.readUser()
    }

    var isAuthenticated: Bool { token != nil }

    func save(token: String, user: HarvestUser) {
        self.token = token
        self.user = user
        persistence.writeToken(token)
        persistence.writeUser(user)
    }

    func updateUser(_ user: HarvestUser) {
        self.user = user
        persistence.writeUser(user)
    }

    func clear() {
        token = nil
        user = nil
        persistence.writeToken(nil)
        persistence.writeUser(nil)
    }
}
