import Foundation
import Security

public enum APIKeyStoreError: Error, Sendable, Equatable, LocalizedError {
    case keychainError(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Gemini API key data is invalid."
        case .keychainError(let status):
            return "Keychain error \(status) while reading the Gemini API key."
        }
    }
}

/// Test seam for code that needs credentials without touching the simulator Keychain.
public protocol APIKeyStoreBackend: Sendable {
    func save(_ value: String, kind: APIKeyKind) throws
    func load(kind: APIKeyKind) throws -> String?
    func delete(kind: APIKeyKind) throws
}

public final class InMemoryAPIKeyStoreBackend: APIKeyStoreBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [APIKeyKind: String] = [:]

    public init() {}

    public func save(_ value: String, kind: APIKeyKind) throws {
        guard !value.isEmpty else { throw APIKeyStoreError.invalidData }
        lock.withLock { values[kind] = value }
    }

    public func load(kind: APIKeyKind) throws -> String? {
        lock.withLock { values[kind] }
    }

    public func delete(kind: APIKeyKind) throws {
        lock.withLock { values.removeValue(forKey: kind) }
    }
}

public struct APIKeyStore: Sendable {
    public static let defaultService = "com.cameronro.helm.apikeys"

    private let service: String
    private let backend: (any APIKeyStoreBackend)?

    public init(
        service: String = APIKeyStore.defaultService,
        backend: (any APIKeyStoreBackend)? = nil
    ) {
        self.service = service
        self.backend = backend
    }

    public func save(_ value: String, kind: APIKeyKind) throws {
        if let backend {
            try backend.save(value, kind: kind)
            return
        }
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
        if let backend {
            return try backend.load(kind: kind)
        }
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
        if let backend {
            try backend.delete(kind: kind)
            return
        }
        let status = SecItemDelete(baseQuery(for: kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainError(status)
        }
    }

    public func hasKey(kind: APIKeyKind) -> Bool {
        (try? load(kind: kind)) != nil
    }

    /// Masked key for UI. Never returns the raw secret.
    public func displayValue(for kind: APIKeyKind) -> String {
        maskedDisplayValue(for: kind)
    }

    public func maskedDisplayValue(for kind: APIKeyKind) -> String {
        guard let value = try? load(kind: kind) else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= 4 { return "••••" }
        return "••••" + String(trimmed.suffix(4))
    }

    private func baseQuery(for kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
    }
}
