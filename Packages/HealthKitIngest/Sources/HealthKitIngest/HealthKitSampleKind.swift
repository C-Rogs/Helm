import Foundation
import HealthKit

public enum HealthKitSampleKind: String, Sendable, CaseIterable, Codable {
    case hrvSDNN
    case restingHeartRate
    case sleep
    case respiratoryRate
    case wristTemperature
    case activeEnergy
    case dietaryEnergy
    case dietaryProtein
    case dietaryCarbohydrate
    case dietaryFat
    case bodyMass
    case workout

    public var metricFamily: HealthKitMetricFamily {
        switch self {
        case .hrvSDNN, .restingHeartRate, .respiratoryRate, .wristTemperature:
            .vitals
        case .activeEnergy:
            .activity
        case .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat:
            .nutrition
        case .bodyMass:
            .bodyComposition
        case .sleep:
            .sleep
        case .workout:
            .workouts
        }
    }

    public var anchorKey: String { rawValue }

    public var backgroundDeliveryFrequency: HKUpdateFrequency {
        switch self {
        case .workout:
            .immediate
        case .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat:
            .hourly
        default:
            .hourly
        }
    }

    public var objectType: HKObjectType {
        switch self {
        case .hrvSDNN:
            HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate:
            HKQuantityType(.restingHeartRate)
        case .sleep:
            HKCategoryType(.sleepAnalysis)
        case .respiratoryRate:
            HKQuantityType(.respiratoryRate)
        case .wristTemperature:
            HKQuantityType(.appleSleepingWristTemperature)
        case .activeEnergy:
            HKQuantityType(.activeEnergyBurned)
        case .dietaryEnergy:
            HKQuantityType(.dietaryEnergyConsumed)
        case .dietaryProtein:
            HKQuantityType(.dietaryProtein)
        case .dietaryCarbohydrate:
            HKQuantityType(.dietaryCarbohydrates)
        case .dietaryFat:
            HKQuantityType(.dietaryFatTotal)
        case .bodyMass:
            HKQuantityType(.bodyMass)
        case .workout:
            HKWorkoutType.workoutType()
        }
    }

    public var sampleType: HKSampleType {
        switch objectType {
        case let sample as HKSampleType:
            sample
        default:
            preconditionFailure("unexpected object type for \(rawValue)")
        }
    }

    public static var readTypes: Set<HKObjectType> {
        var types = Set(allCases.map(\.objectType))
        types.insert(HKQuantityType(.heartRate))
        types.insert(HKQuantityType(.height))
        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }
        return types
    }

    public static var shareTypes: Set<HKSampleType> {
        [
            HKWorkoutType.workoutType(),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryProtein),
            HKQuantityType(.dietaryCarbohydrates),
            HKQuantityType(.dietaryFatTotal)
        ]
    }
}
