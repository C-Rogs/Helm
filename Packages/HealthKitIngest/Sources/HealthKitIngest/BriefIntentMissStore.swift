import Core
import Foundation
import Persistence

public struct BriefIntentMissStore: Sendable {
    public static let metadataKey = "brief_intent_missed_day"

    private let metadata: AppMetadataStore

    public init(metadata: AppMetadataStore) {
        self.metadata = metadata
    }

    public func pendingMissDay() throws -> HelmDay? {
        guard let raw = try metadata.value(forKey: Self.metadataKey) else {
            return nil
        }
        return Self.helmDay(from: raw)
    }

    public func hasPendingMiss(for day: HelmDay) throws -> Bool {
        try pendingMissDay() == day
    }

    public func recordMiss(for day: HelmDay) throws {
        try metadata.setValue(day.formatted, forKey: Self.metadataKey)
    }

    public func clearMiss(for day: HelmDay) throws {
        guard try pendingMissDay() == day else { return }
        try metadata.setValue(nil, forKey: Self.metadataKey)
    }

    private static func helmDay(from formatted: String) -> HelmDay? {
        let parts = formatted.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
