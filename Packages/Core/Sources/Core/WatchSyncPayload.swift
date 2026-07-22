import Foundation

/// Last-write-wins application-context payload shared between iPhone and Watch.
public struct WatchSyncPayload: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable {
        case phone
        case watch
    }

    public static let contextKey = "helm.sync"

    public let origin: Origin
    public let sequence: Int
    public let helmDay: String
    public let sentAt: TimeInterval

    public init(origin: Origin, sequence: Int, helmDay: HelmDay, sentAt: TimeInterval) {
        self.origin = origin
        self.sequence = sequence
        self.helmDay = helmDay.formatted
        self.sentAt = sentAt
    }
}

public extension WatchSyncPayload {
    func applicationContext() -> [String: Any] {
        guard
            let data = try? JSONEncoder().encode(self),
            let object = try? JSONSerialization.jsonObject(with: data),
            let json = object as? [String: Any]
        else {
            return [:]
        }
        return [Self.contextKey: json]
    }

    static func from(applicationContext: [String: Any]) -> WatchSyncPayload? {
        guard let json = applicationContext[contextKey] else { return nil }
        guard JSONSerialization.isValidJSONObject(json) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(WatchSyncPayload.self, from: data)
    }
}
