import Foundation

// Parses incoming URLs dispatched via `.onOpenURL`. Kept standalone from
// AppModel so unit tests can hit it without touching SwiftUI.
enum UniversalLinks {

    /// Returns the magic-link token if `url` matches
    /// `https://harvest.bitrat.io/auth/verify?token=…`. Returns nil for any
    /// other URL (including any custom scheme, other paths, or a missing
    /// token query param).
    static func verifyToken(from url: URL) -> String? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "https",
            components.host == "harvest.bitrat.io",
            components.path == "/auth/verify",
            let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
            !token.isEmpty
        else {
            return nil
        }
        return token
    }
}
