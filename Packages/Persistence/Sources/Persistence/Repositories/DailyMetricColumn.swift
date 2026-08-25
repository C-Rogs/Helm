import Core
import Foundation

/// Column filters for listing stored daily metric days (debug browser).
public enum DailyMetricColumn: String, Sendable, CaseIterable {
    case hrvSDNN = "hrv_sdnn_ms"
    case restingHeartRate = "resting_heart_rate"
    case respiratoryRate = "respiratory_rate"
    case wristTemperatureDeltaCelsius = "wrist_temperature_delta_celsius"
    case activeEnergy = "active_energy_kcal"
    case dietaryEnergy = "dietary_energy_kcal"
    case dietaryProtein = "dietary_protein_grams"
    case dietaryCarbohydrate = "dietary_carbohydrate_grams"
    case dietaryFat = "dietary_fat_grams"
    case priorDayTRIMP = "prior_day_trimp"
    case stepCount = "step_count"
    case restingEnergy = "resting_energy_kcal"

    public var displayName: String {
        switch self {
        case .hrvSDNN: "HRV (SDNN)"
        case .restingHeartRate: "Resting HR"
        case .respiratoryRate: "Respiratory rate"
        case .wristTemperatureDeltaCelsius: "Wrist temperature"
        case .activeEnergy: "Active energy"
        case .dietaryEnergy: "Dietary energy"
        case .dietaryProtein: "Protein"
        case .dietaryCarbohydrate: "Carbohydrates"
        case .dietaryFat: "Fat"
        case .priorDayTRIMP: "Prior-day TRIMP"
        case .stepCount: "Steps"
        case .restingEnergy: "Resting energy"
        }
    }
}
