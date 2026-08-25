import Core
import Foundation
import GRDB

struct DailyMetricsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "daily_metrics"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case hrvSDNNMs = "hrv_sdnn_ms"
        case restingHeartRate = "resting_heart_rate"
        case respiratoryRate = "respiratory_rate"
        case wristTemperatureDeltaCelsius = "wrist_temperature_delta_celsius"
        case activeEnergyKcal = "active_energy_kcal"
        case dietaryEnergyKcal = "dietary_energy_kcal"
        case dietaryProteinGrams = "dietary_protein_grams"
        case dietaryCarbohydrateGrams = "dietary_carbohydrate_grams"
        case dietaryFatGrams = "dietary_fat_grams"
        case priorDayTRIMP = "prior_day_trimp"
        case stepCount = "step_count"
        case restingEnergyKcal = "resting_energy_kcal"
        case updatedAt = "updated_at"
    }

    var helmDay: String
    var hrvSDNNMs: Int?
    var restingHeartRate: Int?
    var respiratoryRate: Double?
    var wristTemperatureDeltaCelsius: Double?
    var activeEnergyKcal: Double?
    var dietaryEnergyKcal: Double?
    var dietaryProteinGrams: Double?
    var dietaryCarbohydrateGrams: Double?
    var dietaryFatGrams: Double?
    var priorDayTRIMP: Double?
    var stepCount: Int?
    var restingEnergyKcal: Double?
    var updatedAt: String

    init(metrics: DailyMetrics, timestamp: Date = Date()) {
        helmDay = HelmDayColumn.encode(metrics.helmDay)
        hrvSDNNMs = metrics.hrvSDNN?.milliseconds
        restingHeartRate = metrics.restingHeartRate
        respiratoryRate = metrics.respiratoryRate
        wristTemperatureDeltaCelsius = metrics.wristTemperatureDeltaCelsius
        activeEnergyKcal = metrics.activeEnergy?.kilocalories
        dietaryEnergyKcal = metrics.dietaryEnergy?.kilocalories
        dietaryProteinGrams = metrics.dietaryProteinGrams
        dietaryCarbohydrateGrams = metrics.dietaryCarbohydrateGrams
        dietaryFatGrams = metrics.dietaryFatGrams
        priorDayTRIMP = metrics.priorDayTRIMP
        stepCount = metrics.stepCount
        restingEnergyKcal = metrics.restingEnergyKcal
        updatedAt = ISO8601Coding.string(from: timestamp)
    }

    func toValue() throws -> DailyMetrics {
        DailyMetrics(
            helmDay: try HelmDayColumn.decode(helmDay),
            hrvSDNN: hrvSDNNMs.map(DurationMs.init(milliseconds:)),
            restingHeartRate: restingHeartRate,
            respiratoryRate: respiratoryRate,
            wristTemperatureDeltaCelsius: wristTemperatureDeltaCelsius,
            activeEnergy: activeEnergyKcal.map { Energy(kilocalories: $0) },
            dietaryEnergy: dietaryEnergyKcal.map { Energy(kilocalories: $0) },
            dietaryProteinGrams: dietaryProteinGrams,
            dietaryCarbohydrateGrams: dietaryCarbohydrateGrams,
            dietaryFatGrams: dietaryFatGrams,
            priorDayTRIMP: priorDayTRIMP,
            stepCount: stepCount,
            restingEnergyKcal: restingEnergyKcal
        )
    }
}
