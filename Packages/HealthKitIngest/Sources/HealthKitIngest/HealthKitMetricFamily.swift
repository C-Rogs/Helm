import Foundation

public enum HealthKitMetricFamily: String, Sendable, CaseIterable, Codable {
    case vitals
    case activity
    case nutrition
    case bodyComposition
    case sleep
    case workouts
}
