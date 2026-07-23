import Foundation
import Security

/// Stable per-install device id for capped OpenRouter key provisioning (M11.2).
public enum HelmDeviceIdentity {
    public enum Error: Swift.Error, Sendable, Equatable {
        case keychainSaveFailed(OSStatus)
    }

    private static let service = "com.cameronro.helm.device-identity"
    private static let account = "default"

    public static func deviceId() throws -> String {
        if let existing = readId() {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        try saveId(generated)
        return generated
    }

    private static func readId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func saveId(_ id: String) throws {
        let data = Data(id.utf8)
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
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw Error.keychainSaveFailed(addStatus)
            }
        default:
            throw Error.keychainSaveFailed(updateStatus)
        }
    }
}
