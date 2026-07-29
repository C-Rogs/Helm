import Foundation

/// Nightly sleep totals for a wake calendar day (18:00–18:00 window).
public struct SleepNightSummary: Sendable, Equatable {
    public let asleepHours: Double?
    public let inBedHours: Double?
    public let awakeMinutes: Double?
    public let deepMinutes: Double?
    public let remMinutes: Double?
    /// Fraction asleep while in bed (0–1), matching Apple Health sleep efficiency when in-bed data exists.
    public let efficiency: Double?

    public init(
        asleepHours: Double?,
        inBedHours: Double? = nil,
        awakeMinutes: Double? = nil,
        deepMinutes: Double? = nil,
        remMinutes: Double? = nil,
        efficiency: Double? = nil
    ) {
        self.asleepHours = asleepHours
        self.inBedHours = inBedHours
        self.awakeMinutes = awakeMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.efficiency = efficiency
    }

    public var wasoMinutes: Double? { awakeMinutes }
}
