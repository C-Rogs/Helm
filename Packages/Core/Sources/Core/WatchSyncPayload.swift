import Foundation

/// Last-write-wins application-context payload shared between iPhone and Watch.
public struct WatchSyncPayload: Codable, Sendable, Equatable {
    public enum Origin: String, Codable, Sendable {
        case phone
        case watch
    }

    public enum MessageKind: String, Codable, Sendable {
        case ping
        case readiness
        case liveHeartRate
    }

    public static let contextKey = "helm.sync"
    public static let briefDeepLink = "helmwatch://brief"
    public static let readinessPushThrottleInterval: TimeInterval = 900
    public static let liveHeartRatePushThrottleInterval: TimeInterval = 5

    public let origin: Origin
    public let sequence: Int
    public let helmDay: String
    public let sentAt: TimeInterval
    public let messageKind: MessageKind
    public let readinessScore: Int?
    public let readinessBand: String?
    public let briefSummary: String?
    /// Opportunistic live HR from Watch during an active session. Never used as source of truth.
    public let liveHeartRateBPM: Int?

    public init(
        origin: Origin,
        sequence: Int,
        helmDay: HelmDay,
        sentAt: TimeInterval,
        messageKind: MessageKind = .ping,
        readinessScore: Int? = nil,
        readinessBand: String? = nil,
        briefSummary: String? = nil,
        liveHeartRateBPM: Int? = nil
    ) {
        self.origin = origin
        self.sequence = sequence
        self.helmDay = helmDay.formatted
        self.sentAt = sentAt
        self.messageKind = messageKind
        self.readinessScore = readinessScore
        self.readinessBand = readinessBand
        self.briefSummary = briefSummary
        self.liveHeartRateBPM = liveHeartRateBPM
    }

    private enum CodingKeys: String, CodingKey {
        case origin
        case sequence
        case helmDay
        case sentAt
        case messageKind
        case readinessScore
        case readinessBand
        case briefSummary
        case liveHeartRateBPM
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(Origin.self, forKey: .origin)
        sequence = try container.decode(Int.self, forKey: .sequence)
        helmDay = try container.decode(String.self, forKey: .helmDay)
        sentAt = try container.decode(TimeInterval.self, forKey: .sentAt)
        messageKind = try container.decodeIfPresent(MessageKind.self, forKey: .messageKind) ?? .ping
        readinessScore = try container.decodeIfPresent(Int.self, forKey: .readinessScore)
        readinessBand = try container.decodeIfPresent(String.self, forKey: .readinessBand)
        briefSummary = try container.decodeIfPresent(String.self, forKey: .briefSummary)
        liveHeartRateBPM = try container.decodeIfPresent(Int.self, forKey: .liveHeartRateBPM)
    }
}

public extension WatchSyncPayload {
    var helmDayValue: HelmDay? {
        let parts = helmDay.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

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
