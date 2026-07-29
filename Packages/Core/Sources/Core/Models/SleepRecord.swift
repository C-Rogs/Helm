import Foundation

/// One contiguous sleep interval from HealthKit (may be one of several per night).
public struct SleepRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let helmDay: HelmDay
    public let stage: SleepAnalysisStage
    public let sourceBundleID: String?

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }

    public init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        helmDay: HelmDay,
        stage: SleepAnalysisStage = .asleepUnspecified,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.helmDay = helmDay
        self.stage = stage
        self.sourceBundleID = sourceBundleID
    }

    /// Attributes fragmented sleep to the logical day of sleep onset, not the sample end.
    public static func helmDay(
        forStart start: Date,
        cutoff: DayCutoff = .default,
        calendar: Calendar
    ) -> HelmDay {
        HelmDay.day(for: start, cutoff: cutoff, calendar: calendar)
    }
}
