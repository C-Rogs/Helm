import Core
import Foundation
import Persistence
import ReadinessKit

public struct IllnessEarlyWarningStore: Sendable {
    public static let surfacedDayKey = "illness_early_warning_surfaced_day"
    public static let surfacedIDKey = "illness_early_warning_surfaced_id"

    private let metadata: AppMetadataStore

    public init(metadata: AppMetadataStore) {
        self.metadata = metadata
    }

    public func surfacedRecord() throws -> (day: HelmDay, warningID: String)? {
        guard let dayRaw = try metadata.value(forKey: Self.surfacedDayKey),
              let warningID = try metadata.value(forKey: Self.surfacedIDKey),
              let day = helmDay(from: dayRaw) else {
            return nil
        }
        return (day, warningID)
    }

    public func shouldSurface(_ warning: IllnessEarlyWarning, on day: HelmDay) throws -> Bool {
        guard let record = try surfacedRecord() else { return true }
        if record.day != day { return true }
        return record.warningID != warning.id
    }

    public func markSurfaced(_ warning: IllnessEarlyWarning, on day: HelmDay) throws {
        try metadata.setValue(day.formatted, forKey: Self.surfacedDayKey)
        try metadata.setValue(warning.id, forKey: Self.surfacedIDKey)
    }

    private func helmDay(from formatted: String) -> HelmDay? {
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
