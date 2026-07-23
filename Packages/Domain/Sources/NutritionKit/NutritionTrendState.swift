import Core
import Foundation

public struct NutritionTrendDayInput: Sendable, Hashable, Codable, Equatable {
    public let helmDay: HelmDay
    public let bodyMassKg: Double?
    public let loggedIntakeKcal: Double?

    public init(helmDay: HelmDay, bodyMassKg: Double? = nil, loggedIntakeKcal: Double? = nil) {
        self.helmDay = helmDay
        self.bodyMassKg = bodyMassKg
        self.loggedIntakeKcal = loggedIntakeKcal
    }
}

public struct NutritionTrendState: Sendable, Hashable, Codable, Equatable {
    public var estimatedTDEEKcal: Double?
    public var smoothedTrendWeightKg: Double?
    public var priorWeekTrendWeightKg: Double?
    public var weeklyIntakeAverageKcal: Double?
    public var lastWeeklyUpdate: HelmDay?

    public init(
        estimatedTDEEKcal: Double? = nil,
        smoothedTrendWeightKg: Double? = nil,
        priorWeekTrendWeightKg: Double? = nil,
        weeklyIntakeAverageKcal: Double? = nil,
        lastWeeklyUpdate: HelmDay? = nil
    ) {
        self.estimatedTDEEKcal = estimatedTDEEKcal
        self.smoothedTrendWeightKg = smoothedTrendWeightKg
        self.priorWeekTrendWeightKg = priorWeekTrendWeightKg
        self.weeklyIntakeAverageKcal = weeklyIntakeAverageKcal
        self.lastWeeklyUpdate = lastWeeklyUpdate
    }
}
