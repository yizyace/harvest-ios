import Foundation
import Security

// Keychain-backed `SessionPersistence`. The access group is shared with the
// Share Extension (both targets declare the same keychain-access-groups
// entitlement), which lets the extension POST bookmarks using the same
// session token the main app acquired during sign-in.
struct KeychainSessionPersistence: SessionPersistence {

    private let service = "io.bitrat.harvest"
    private let accessGroup = "37A42LB22L.io.bitrat.harvest"
    private let tokenAccount = "session_token"
    private let userAccount = "session_user"

    func readToken() -> String? {
        guard let data = read(account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeToken(_ token: String?) {
        if let token, let data = token.data(using: .utf8) {
            write(account: tokenAccount, data: data)
        } else {
            delete(account: tokenAccount)
        }
    }

    func readUser() -> HarvestUser? {
        guard let data = read(account: userAccount) else { return nil }
        return try? ISO8601JSON.makeDecoder().decode(HarvestUser.self, from: data)
    }

    func writeUser(_ user: HarvestUser?) {
        if let user, let data = try? ISO8601JSON.makeEncoder().encode(user) {
            write(account: userAccount, data: data)
        } else {
            delete(account: userAccount)
        }
    }

    // MARK: - Keychain primitives

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    private func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func write(account: String, data: Data) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
