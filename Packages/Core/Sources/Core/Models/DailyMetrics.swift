import Foundation

/// Aggregated health metrics for one logical day.
public struct DailyMetrics: Sendable, Hashable, Codable, Identifiable {
    public let helmDay: HelmDay
    public let hrvSDNN: DurationMs?
    public let restingHeartRate: Int?
    public let respiratoryRate: Double?
    public let wristTemperatureDeltaCelsius: Double?
    public let activeEnergy: Energy?
    public let dietaryEnergy: Energy?
    public let dietaryProteinGrams: Double?
    public let dietaryCarbohydrateGrams: Double?
    public let dietaryFatGrams: Double?
    public let priorDayTRIMP: Double?

    public var id: HelmDay { helmDay }

    public init(
        helmDay: HelmDay,
        hrvSDNN: DurationMs? = nil,
        restingHeartRate: Int? = nil,
        respiratoryRate: Double? = nil,
        wristTemperatureDeltaCelsius: Double? = nil,
        activeEnergy: Energy? = nil,
        dietaryEnergy: Energy? = nil,
        dietaryProteinGrams: Double? = nil,
        dietaryCarbohydrateGrams: Double? = nil,
        dietaryFatGrams: Double? = nil,
        priorDayTRIMP: Double? = nil
    ) {
        self.helmDay = helmDay
        self.hrvSDNN = hrvSDNN
        self.restingHeartRate = restingHeartRate
        self.respiratoryRate = respiratoryRate
        self.wristTemperatureDeltaCelsius = wristTemperatureDeltaCelsius
        self.activeEnergy = activeEnergy
        self.dietaryEnergy = dietaryEnergy
        self.dietaryProteinGrams = dietaryProteinGrams
        self.dietaryCarbohydrateGrams = dietaryCarbohydrateGrams
        self.dietaryFatGrams = dietaryFatGrams
        self.priorDayTRIMP = priorDayTRIMP
    }
}
