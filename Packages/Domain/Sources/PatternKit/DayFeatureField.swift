import Foundation

public enum DayFeatureKind: String, Sendable, Hashable, Codable, CaseIterable {
    case binary
    case continuous
    case categorical
    case residual
}

public enum DayFeatureField: String, Sendable, Hashable, Codable, CaseIterable {
    case alcohol
    case breakfastLogged = "breakfast_logged"
    case trainingDay = "training_day"
    case dietEnergyKcal = "diet_energy_kcal"
    case dietProteinG = "diet_protein_g"
    case sleepAsleepMin = "sleep_asleep_min"
    case sleepRemMin = "sleep_rem_min"
    case sleepEfficiency = "sleep_efficiency"
    case hrvSdnn = "hrv_sdnn"
    case restingHr = "resting_hr"
    case arcScore = "arc_score"
    case arcBand = "arc_band"
    case bodyMassKg = "bodymass_kg"
    case workoutMinutes = "workout_minutes"
    case sessionVolumeKg = "session_volume_kg"
    case priorDayTrimp = "prior_day_trimp"
    case dayDemand = "day_demand"
    case hardSetCount = "hard_set_count"
    case energyResidual = "energy_residual"
    case volumeResidual = "volume_residual"

    public var kind: DayFeatureKind {
        switch self {
        case .alcohol, .breakfastLogged, .trainingDay:
            .binary
        case .arcBand, .dayDemand:
            .categorical
        case .energyResidual, .volumeResidual:
            .residual
        case .dietEnergyKcal, .dietProteinG, .sleepAsleepMin, .sleepRemMin, .sleepEfficiency,
             .hrvSdnn, .restingHr, .arcScore, .bodyMassKg, .workoutMinutes, .sessionVolumeKg,
             .priorDayTrimp, .hardSetCount:
            .continuous
        }
    }

    public var displayName: String {
        switch self {
        case .alcohol: "alcohol"
        case .breakfastLogged: "breakfast"
        case .trainingDay: "training day"
        case .dietEnergyKcal: "dietary energy"
        case .dietProteinG: "dietary protein"
        case .sleepAsleepMin: "sleep duration"
        case .sleepRemMin: "REM sleep"
        case .sleepEfficiency: "sleep efficiency"
        case .hrvSdnn: "HRV"
        case .restingHr: "resting heart rate"
        case .arcScore: "ARC score"
        case .arcBand: "ARC band"
        case .bodyMassKg: "body mass"
        case .workoutMinutes: "workout minutes"
        case .sessionVolumeKg: "session volume"
        case .priorDayTrimp: "prior-day TRIMP"
        case .dayDemand: "day demand"
        case .hardSetCount: "hard sets"
        case .energyResidual: "energy vs eat-to"
        case .volumeResidual: "volume vs prescription"
        }
    }
}
