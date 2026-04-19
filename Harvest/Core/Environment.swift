import Foundation

// Reads the API base URL from the Info.plist (populated from the per-config
// xcconfig at build time). Defaults to the production URL if the key is
// missing so we never ship a broken build.
enum AppEnvironment {
    static var apiBaseURL: URL {
        let fallback = URL(string: "https://harvest.bitrat.io")!
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            !raw.isEmpty,
            let url = URL(string: raw)
        else {
            return fallback
        }
        return url
    }
}
