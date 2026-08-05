import Core
import Foundation
import Security

/// Persists the Spotify PKCE session (access token, refresh token, expiry) in the Keychain.
enum SpotifySessionStore {
    private static let service = "com.cameronro.helm.spotify"
    private static let account = "oauth_session"
    /// Pre-PKCE builds stored a bare access token with no refresh token or expiry.
    private static let legacyAccount = "access_token"

    static var isConnected: Bool {
        load() != nil
    }

    static func load() -> SpotifyAuthSession? {
        guard let data = read(account: account) else { return nil }
        return try? JSONDecoder().decode(SpotifyAuthSession.self, from: data)
    }

    @discardableResult
    static func save(_ session: SpotifyAuthSession) -> OSStatus {
        guard let data = try? JSONEncoder().encode(session) else { return errSecParam }
        delete(account: legacyAccount)
        return write(data, account: account)
    }

    static func clear() {
        delete(account: account)
        delete(account: legacyAccount)
    }

    private static func write(_ data: Data, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
