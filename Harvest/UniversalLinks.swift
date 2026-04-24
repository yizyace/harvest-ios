import Foundation

// Parses incoming URLs dispatched via `.onOpenURL`. Kept standalone from
// AppModel so unit tests can hit it without touching SwiftUI.
enum UniversalLinks {

    /// Returns the magic-link token if `url` matches
    /// `https://<expectedHost>/auth/verify?token=…`. Returns nil for any
    /// other URL (including any custom scheme, other paths, or a missing
    /// token query param).
    ///
    /// `expectedHost` is injected so prod and dev builds each only accept
    /// their own backend's host — the caller passes
    /// `AppEnvironment.current.baseURL.host`.
    static func verifyToken(from url: URL, expectedHost: String) -> String? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "https",
            components.host == expectedHost,
            components.path == "/auth/verify",
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
            !token.isEmpty
        else {
            return nil
        }
        return token
    }
}
