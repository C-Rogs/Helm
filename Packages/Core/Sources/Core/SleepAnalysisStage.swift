import Foundation

/// HealthKit sleep-analysis stage persisted with each interval.
public enum SleepAnalysisStage: String, Sendable, Hashable, Codable, CaseIterable {
    case asleepUnspecified
    case asleepCore
    case asleepDeep
    case asleepREM
    case awake
    case inBed

    public var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            true
        case .awake, .inBed:
            false
        }
    }

    public var displayName: String {
        switch self {
        case .asleepUnspecified: "Asleep"
        case .asleepCore: "Core"
        case .asleepDeep: "Deep"
        case .asleepREM: "REM"
        case .awake: "Awake"
        case .inBed: "In bed"
        }
    }
}
