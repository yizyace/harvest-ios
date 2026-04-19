import Foundation

// Env-specific values baked into the Info.plist at build time via xcconfig
// (HARVEST_BASE_URL, HARVEST_SUPPORTS_UNIVERSAL_LINKS, HARVEST_BUNDLE_ID).
// Consumers should route through this type instead of reading Info.plist
// directly or branching on `#if DEBUG` — the handoff explicitly calls out
// "no #if DEBUG branches" as an acceptance criterion.
struct AppEnvironment: Sendable {

    let baseURL: URL
    let supportsUniversalLinks: Bool
    let keychainAccessGroup: String

    static let current: AppEnvironment = {
        let bundle = Bundle.main
        return AppEnvironment(
            baseURL: readURL(bundle: bundle, key: "HarvestBaseURL")
                ?? URL(string: "https://harvest.bitrat.io")!,
            supportsUniversalLinks: readBool(bundle: bundle, key: "HarvestSupportsUniversalLinks"),
            keychainAccessGroup: readString(bundle: bundle, key: "HarvestKeychainGroup")
                ?? "io.bitrat.harvest"
        )
    }()

    private static func readString(bundle: Bundle, key: String) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func readURL(bundle: Bundle, key: String) -> URL? {
        readString(bundle: bundle, key: key).flatMap(URL.init(string:))
    }

    private static func readBool(bundle: Bundle, key: String) -> Bool {
        // Info.plist stores xcconfig-sourced booleans as the literal strings
        // "YES"/"NO" because xcconfig has no bool type. Accept either that or
        // an actual bool (Xcode may coerce for generated plists).
        if let bool = bundle.object(forInfoDictionaryKey: key) as? Bool { return bool }
        if let string = readString(bundle: bundle, key: key) {
            return string.uppercased() == "YES" || string == "1" || string.lowercased() == "true"
        }
        return false
    }
}
