import Foundation

public enum HealthKitStatus: String, Codable, Sendable {
    case liveAuthorized = "live_authorized"
    case notDetermined = "not_determined"
    case denied
    case unavailable
    case error
}

public struct RoundedDouble: Codable, Equatable, Sendable {
    public let value: Double

    public init?(_ raw: Double?) {
        guard let raw else { return nil }
        value = (raw * 100).rounded() / 100
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Double.self)
    }
}

extension KeyedEncodingContainer {
    mutating func encodeNullOrRoundedDouble(_ value: RoundedDouble?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }

    mutating func encodeNullOrInt(_ value: Int?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

public struct ExportRange: Codable, Equatable, Sendable {
    public let startDate: String
    public let endDate: String

    public init(startDate: String, endDate: String) {
        self.startDate = startDate
        self.endDate = endDate
    }

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

public struct ExportPayload: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let app: String
    public let purpose: String
    public let exportDate: Date
    public let healthKitStatus: HealthKitStatus
    public let exportRange: ExportRange
    public let logs: [DailyLog]

    public init(
        schemaVersion: Int,
        app: String,
        purpose: String,
        exportDate: Date,
        healthKitStatus: HealthKitStatus,
        exportRange: ExportRange,
        logs: [DailyLog]
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.purpose = purpose
        self.exportDate = exportDate
        self.healthKitStatus = healthKitStatus
        self.exportRange = exportRange
        self.logs = logs
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case app
        case purpose
        case exportDate = "export_date"
        case healthKitStatus = "healthkit_status"
        case exportRange = "export_range"
        case logs
    }
}

public struct DailyLog: Codable, Equatable, Sendable {
    public let date: String
    public let timezone: String
    public let cnsAndCardio: CNSAndCardioMetrics
    public let sleepAndRecovery: SleepAndRecoveryMetrics
    public let nutritionAndToxicity: NutritionAndToxicityMetrics
    public let activityAndStrain: ActivityAndStrainMetrics
    public let bodyComposition: BodyCompositionMetrics

    public init(
        date: String,
        timezone: String,
        cnsAndCardio: CNSAndCardioMetrics,
        sleepAndRecovery: SleepAndRecoveryMetrics,
        nutritionAndToxicity: NutritionAndToxicityMetrics,
        activityAndStrain: ActivityAndStrainMetrics,
        bodyComposition: BodyCompositionMetrics
    ) {
        self.date = date
        self.timezone = timezone
        self.cnsAndCardio = cnsAndCardio
        self.sleepAndRecovery = sleepAndRecovery
        self.nutritionAndToxicity = nutritionAndToxicity
        self.activityAndStrain = activityAndStrain
        self.bodyComposition = bodyComposition
    }

    enum CodingKeys: String, CodingKey {
        case date
        case timezone
        case cnsAndCardio = "cns_and_cardio"
        case sleepAndRecovery = "sleep_and_recovery"
        case nutritionAndToxicity = "nutrition_and_toxicity"
        case activityAndStrain = "activity_and_strain"
        case bodyComposition = "body_composition"
    }
}

public struct CNSAndCardioMetrics: Codable, Equatable, Sendable {
    public let restingHeartRate: RoundedDouble?
    public let hrvSdnn: RoundedDouble?

    public init(restingHeartRate: RoundedDouble?, hrvSdnn: RoundedDouble?) {
        self.restingHeartRate = restingHeartRate
        self.hrvSdnn = hrvSdnn
    }

    enum CodingKeys: String, CodingKey {
        case restingHeartRate = "resting_heart_rate"
        case hrvSdnn = "hrv_sdnn"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullOrRoundedDouble(restingHeartRate, forKey: .restingHeartRate)
        try container.encodeNullOrRoundedDouble(hrvSdnn, forKey: .hrvSdnn)
    }
}

public struct SleepAndRecoveryMetrics: Codable, Equatable, Sendable {
    public let sleepTotalMinutes: RoundedDouble?
    public let deepSleepMinutes: RoundedDouble?
    public let remSleepMinutes: RoundedDouble?

    public init(
        sleepTotalMinutes: RoundedDouble?,
        deepSleepMinutes: RoundedDouble?,
        remSleepMinutes: RoundedDouble?
    ) {
        self.sleepTotalMinutes = sleepTotalMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
    }

    enum CodingKeys: String, CodingKey {
        case sleepTotalMinutes = "sleep_total_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullOrRoundedDouble(sleepTotalMinutes, forKey: .sleepTotalMinutes)
        try container.encodeNullOrRoundedDouble(deepSleepMinutes, forKey: .deepSleepMinutes)
        try container.encodeNullOrRoundedDouble(remSleepMinutes, forKey: .remSleepMinutes)
    }
}

public struct NutritionAndToxicityMetrics: Codable, Equatable, Sendable {
    public let caloriesConsumedKcal: RoundedDouble?
    public let proteinG: RoundedDouble?
    public let carbsG: RoundedDouble?
    public let fatG: RoundedDouble?
    public let waterLiters: RoundedDouble?
    public let alcoholicBeveragesCount: Int?

    public init(
        caloriesConsumedKcal: RoundedDouble?,
        proteinG: RoundedDouble?,
        carbsG: RoundedDouble?,
        fatG: RoundedDouble?,
        waterLiters: RoundedDouble?,
        alcoholicBeveragesCount: Int?
    ) {
        self.caloriesConsumedKcal = caloriesConsumedKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.waterLiters = waterLiters
        self.alcoholicBeveragesCount = alcoholicBeveragesCount
    }

    enum CodingKeys: String, CodingKey {
        case caloriesConsumedKcal = "calories_consumed_kcal"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case waterLiters = "water_liters"
        case alcoholicBeveragesCount = "alcoholic_beverages_count"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullOrRoundedDouble(caloriesConsumedKcal, forKey: .caloriesConsumedKcal)
        try container.encodeNullOrRoundedDouble(proteinG, forKey: .proteinG)
        try container.encodeNullOrRoundedDouble(carbsG, forKey: .carbsG)
        try container.encodeNullOrRoundedDouble(fatG, forKey: .fatG)
        try container.encodeNullOrRoundedDouble(waterLiters, forKey: .waterLiters)
        try container.encodeNullOrInt(alcoholicBeveragesCount, forKey: .alcoholicBeveragesCount)
    }
}

public struct WorkoutLog: Codable, Equatable, Sendable {
    public let type: String
    public let durationMinutes: RoundedDouble?
    public let energyBurnedKcal: RoundedDouble?
    public let effortScore: RoundedDouble?
    public let trainingLoadContribution: RoundedDouble?

    public init(
        type: String,
        durationMinutes: RoundedDouble?,
        energyBurnedKcal: RoundedDouble?,
        effortScore: RoundedDouble?,
        trainingLoadContribution: RoundedDouble?
    ) {
        self.type = type
        self.durationMinutes = durationMinutes
        self.energyBurnedKcal = energyBurnedKcal
        self.effortScore = effortScore
        self.trainingLoadContribution = trainingLoadContribution
    }

    enum CodingKeys: String, CodingKey {
        case type
        case durationMinutes = "duration_minutes"
        case energyBurnedKcal = "energy_burned_kcal"
        case effortScore = "effort_score"
        case trainingLoadContribution = "training_load_contribution"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeNullOrRoundedDouble(durationMinutes, forKey: .durationMinutes)
        try container.encodeNullOrRoundedDouble(energyBurnedKcal, forKey: .energyBurnedKcal)
        try container.encodeNullOrRoundedDouble(effortScore, forKey: .effortScore)
        try container.encodeNullOrRoundedDouble(trainingLoadContribution, forKey: .trainingLoadContribution)
    }
}

public struct ActivityAndStrainMetrics: Codable, Equatable, Sendable {
    public let stepCount: Int?
    public let activeEnergyKcal: RoundedDouble?
    public let restingEnergyKcal: RoundedDouble?
    public let exerciseMinutes: RoundedDouble?
    public let trainingLoadContribution: RoundedDouble?
    public let workouts: [WorkoutLog]

    public init(
        stepCount: Int?,
        activeEnergyKcal: RoundedDouble?,
        restingEnergyKcal: RoundedDouble?,
        exerciseMinutes: RoundedDouble?,
        trainingLoadContribution: RoundedDouble?,
        workouts: [WorkoutLog]
    ) {
        self.stepCount = stepCount
        self.activeEnergyKcal = activeEnergyKcal
        self.restingEnergyKcal = restingEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.trainingLoadContribution = trainingLoadContribution
        self.workouts = workouts
    }

    enum CodingKeys: String, CodingKey {
        case stepCount = "step_count"
        case activeEnergyKcal = "active_energy_kcal"
        case restingEnergyKcal = "resting_energy_kcal"
        case exerciseMinutes = "exercise_minutes"
        case trainingLoadContribution = "training_load_contribution"
        case workouts
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullOrInt(stepCount, forKey: .stepCount)
        try container.encodeNullOrRoundedDouble(activeEnergyKcal, forKey: .activeEnergyKcal)
        try container.encodeNullOrRoundedDouble(restingEnergyKcal, forKey: .restingEnergyKcal)
        try container.encodeNullOrRoundedDouble(exerciseMinutes, forKey: .exerciseMinutes)
        try container.encodeNullOrRoundedDouble(trainingLoadContribution, forKey: .trainingLoadContribution)
        try container.encode(workouts, forKey: .workouts)
    }
}

public struct BodyCompositionMetrics: Codable, Equatable, Sendable {
    public let bodyWeightKg: RoundedDouble?
    public let bodyFatPercent: RoundedDouble?

    public init(bodyWeightKg: RoundedDouble?, bodyFatPercent: RoundedDouble?) {
        self.bodyWeightKg = bodyWeightKg
        self.bodyFatPercent = bodyFatPercent
    }

    enum CodingKeys: String, CodingKey {
        case bodyWeightKg = "body_weight_kg"
        case bodyFatPercent = "body_fat_percent"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNullOrRoundedDouble(bodyWeightKg, forKey: .bodyWeightKg)
        try container.encodeNullOrRoundedDouble(bodyFatPercent, forKey: .bodyFatPercent)
    }
}
