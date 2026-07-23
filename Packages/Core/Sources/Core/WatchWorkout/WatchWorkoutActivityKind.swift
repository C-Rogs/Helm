import Foundation

/// User-selectable workout types for the Watch session picker.
public enum WatchWorkoutActivityKind: String, CaseIterable, Sendable, Identifiable {
    case traditionalStrengthTraining
    case functionalStrengthTraining
    case running
    case cycling
    case walking
    case highIntensityIntervalTraining
    case mixedCardio
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Strength"
        case .functionalStrengthTraining: "Functional"
        case .running: "Run"
        case .cycling: "Cycle"
        case .walking: "Walk"
        case .highIntensityIntervalTraining: "HIIT"
        case .mixedCardio: "Cardio"
        case .other: "Other"
        }
    }

    public var usesOutdoorLocation: Bool {
        switch self {
        case .running, .cycling, .walking: true
        default: false
        }
    }

    /// Raw HealthKit activity type identifier (mirrors `HKWorkoutActivityType` raw values).
    public var healthKitActivityTypeRawValue: UInt {
        switch self {
        case .traditionalStrengthTraining: 50
        case .functionalStrengthTraining: 20
        case .running: 37
        case .cycling: 13
        case .walking: 52
        case .highIntensityIntervalTraining: 63
        case .mixedCardio: 73
        case .other: 3000
        }
    }
}
