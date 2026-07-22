import Foundation
import Security

public enum APIKeyStoreError: Error, Sendable, Equatable {
    case keychainError(OSStatus)
    case invalidData
}

public struct APIKeyStore: Sendable {
    public static let defaultService = "com.cameronro.helm.apikeys"

    private let service: String

    public init(service: String = APIKeyStore.defaultService) {
        self.service = service
    }

    public func save(_ value: String, kind: APIKeyKind) throws {
        let data = Data(value.utf8)
        guard !data.isEmpty else {
            throw APIKeyStoreError.invalidData
        }

        let query = baseQuery(for: kind)
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
                throw APIKeyStoreError.keychainError(addStatus)
            }
        default:
            throw APIKeyStoreError.keychainError(updateStatus)
        }
    }

    public func load(kind: APIKeyKind) throws -> String? {
        var query = baseQuery(for: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw APIKeyStoreError.invalidData
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw APIKeyStoreError.keychainError(status)
        }
    }

    public func delete(kind: APIKeyKind) throws {
        let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainError(status)
        }
    }

    public func hasKey(kind: APIKeyKind) -> Bool {
        (try? load(kind: kind)) != nil
    }

    private func baseQuery(for kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
    }
}
