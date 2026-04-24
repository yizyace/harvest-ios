import Foundation
import Observation

@Observable
@MainActor
final class AppModel {

    let sessionStore: SessionStore
    let api: HarvestAPI

    /// Set when an API call raises `.unauthorized`. Views render from it;
    /// clearing is automatic once the user signs in again.
    var lastError: String?

    init(sessionStore: SessionStore, api: HarvestAPI) {
        self.sessionStore = sessionStore
        self.api = api
    }

    static func live() -> AppModel {
        let store = SessionStore(persistence: KeychainSessionPersistence())
        // Capture weak-ish: the token-provider closure reads the current
        // SessionStore token on every request, so sign-out propagates to
        // subsequent requests without rebuilding the API client.
        let api = HarvestAPI(
            baseURL: AppEnvironment.current.baseURL,
            urlSession: .shared,
            tokenProvider: { [store] in store.token }
        )
        return AppModel(sessionStore: store, api: api)
    }

    var isSignedIn: Bool { sessionStore.isAuthenticated }

    // MARK: Auth flows

    func sendMagicLink(email: String) async throws {
        try await api.sendMagicLink(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func completeSignIn(withToken token: String) async throws {
        let response = try await api.verify(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        sessionStore.save(token: response.sessionToken, user: response.user)
    }

    func signOut() async {
        // Best-effort: tell the server first, but clear locally regardless —
        // we don't want a network hiccup to strand the user in a logged-in
        // UI state they think is logged out.
        try? await api.signOut()
        sessionStore.clear()
    }

    /// Deletes the account server-side and clears the local session. Only
    /// clears Keychain on a confirmed 204 (or 401 — token already dead from
    /// a prior attempt). Other errors re-throw so the UI can offer retry —
    /// clearing prematurely would leave the user signed out locally while
    /// their account still exists server-side.
    func deleteAccount() async throws {
        do {
            try await api.deleteAccount()
        } catch APIError.unauthorized {
            // Token already invalidated (e.g., prior attempt succeeded
            // server-side but this client didn't see the 204). Same
            // cleanup as success.
        }
        sessionStore.clear()
    }

    /// Call once on app launch. If the stored token is already expired or
    /// revoked server-side, clears the session before the first user action
    /// can paper over the signed-out state.
    func validateSessionOnLaunch() async {
        guard sessionStore.isAuthenticated else { return }
        do {
            let check = try await api.fetchSession()
            if check.authenticated {
                if let user = check.user { sessionStore.updateUser(user) }
            } else {
                sessionStore.clear()
            }
        } catch APIError.unauthorized {
            sessionStore.clear()
        } catch {
            // Transient network errors shouldn't sign the user out — the
            // next authenticated request will re-check anyway.
        }
    }

    // MARK: Handling 401 from anywhere

    /// Call from any view that caught an `APIError`. Non-401 errors surface to
    /// the caller untouched; 401 triggers sign-out and shows `.lastError`.
    func handle(_ error: Error) {
        if let apiError = error as? APIError, case .unauthorized = apiError {
            sessionStore.clear()
            lastError = apiError.userFacingMessage
        }
    }

    // MARK: Incoming URLs (Universal Links + paste-token fallback)

    /// Parses `https://<env-host>/auth/verify?token=…` and completes sign-in.
    /// Returns true if the URL was recognised.
    @discardableResult
    func handleIncomingURL(_ url: URL) async -> Bool {
        guard
            let host = AppEnvironment.current.baseURL.host,
            let token = UniversalLinks.verifyToken(from: url, expectedHost: host)
        else { return false }
        do {
            try await completeSignIn(withToken: token)
            return true
        } catch APIError.unauthorized {
            // Generic "session expired" copy is wrong here — the user never
            // signed in. 401 on /verify means the magic link is stale
            // (expired or already consumed), so ask for a fresh one.
            lastError = "This sign-in link has expired or already been used. Request a new one."
            return false
        } catch {
            lastError = (error as? APIError)?.userFacingMessage ?? "Sign-in failed."
            return false
        }
    }
}
