import Core
import Foundation

/// One logical HelmDay of typed primitives for hypothesis evaluation.
public struct DayFeatureRow: Sendable, Hashable, Codable, Identifiable {
    public var helmDay: HelmDay
    public var weekday: Int
    public var alcohol: Bool?
    public var breakfastLogged: Bool?
    public var trainingDay: Bool?
    public var dietEnergyKcal: Double?
    public var dietProteinG: Double?
    public var sleepAsleepMin: Double?
    public var sleepRemMin: Double?
    public var sleepEfficiency: Double?
    public var hrvSdnn: Double?
    public var restingHr: Double?
    public var arcScore: Double?
    public var arcBand: String?
    public var bodyMassKg: Double?
    public var workoutMinutes: Double?
    public var sessionVolumeKg: Double?
    public var priorDayTrimp: Double?
    public var dayDemand: String?
    public var hardSetCount: Double?
    public var energyResidual: Double?
    public var volumeResidual: Double?

    public var id: HelmDay { helmDay }

    public init(
        helmDay: HelmDay,
        weekday: Int = 1,
        alcohol: Bool? = nil,
        breakfastLogged: Bool? = nil,
        trainingDay: Bool? = nil,
        dietEnergyKcal: Double? = nil,
        dietProteinG: Double? = nil,
        sleepAsleepMin: Double? = nil,
        sleepRemMin: Double? = nil,
        sleepEfficiency: Double? = nil,
        hrvSdnn: Double? = nil,
        restingHr: Double? = nil,
        arcScore: Double? = nil,
        arcBand: String? = nil,
        bodyMassKg: Double? = nil,
        workoutMinutes: Double? = nil,
        sessionVolumeKg: Double? = nil,
        priorDayTrimp: Double? = nil,
        dayDemand: String? = nil,
        hardSetCount: Double? = nil,
        energyResidual: Double? = nil,
        volumeResidual: Double? = nil
    ) {
        self.helmDay = helmDay
        self.weekday = weekday
        self.alcohol = alcohol
        self.breakfastLogged = breakfastLogged
        self.trainingDay = trainingDay
        self.dietEnergyKcal = dietEnergyKcal
        self.dietProteinG = dietProteinG
        self.sleepAsleepMin = sleepAsleepMin
        self.sleepRemMin = sleepRemMin
        self.sleepEfficiency = sleepEfficiency
        self.hrvSdnn = hrvSdnn
        self.restingHr = restingHr
        self.arcScore = arcScore
        self.arcBand = arcBand
        self.bodyMassKg = bodyMassKg
        self.workoutMinutes = workoutMinutes
        self.sessionVolumeKg = sessionVolumeKg
        self.priorDayTrimp = priorDayTrimp
        self.dayDemand = dayDemand
        self.hardSetCount = hardSetCount
        self.energyResidual = energyResidual
        self.volumeResidual = volumeResidual
    }

    public func binary(_ field: DayFeatureField) -> Bool? {
        switch field {
        case .alcohol: alcohol
        case .breakfastLogged: breakfastLogged
        case .trainingDay: trainingDay
        default: nil
        }
    }

    public func continuous(_ field: DayFeatureField) -> Double? {
        switch field {
        case .dietEnergyKcal: dietEnergyKcal
        case .dietProteinG: dietProteinG
        case .sleepAsleepMin: sleepAsleepMin
        case .sleepRemMin: sleepRemMin
        case .sleepEfficiency: sleepEfficiency
        case .hrvSdnn: hrvSdnn
        case .restingHr: restingHr
        case .arcScore: arcScore
        case .bodyMassKg: bodyMassKg
        case .workoutMinutes: workoutMinutes
        case .sessionVolumeKg: sessionVolumeKg
        case .priorDayTrimp: priorDayTrimp
        case .hardSetCount: hardSetCount
        case .energyResidual: energyResidual
        case .volumeResidual: volumeResidual
        default: nil
        }
    }

    public func categorical(_ field: DayFeatureField) -> String? {
        switch field {
        case .arcBand: arcBand
        case .dayDemand: dayDemand
        default: nil
        }
    }

    public func isMissing(_ field: DayFeatureField) -> Bool {
        switch field.kind {
        case .binary: binary(field) == nil
        case .continuous, .residual: continuous(field) == nil
        case .categorical: categorical(field) == nil
        }
    }
}

public enum DayFeatureMissingness {
    /// Diet zeros from HealthKit padding are not true zeros.
    public static func dietValue(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
