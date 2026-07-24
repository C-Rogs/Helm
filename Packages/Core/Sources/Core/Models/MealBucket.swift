import Foundation

/// Meal slot within a logical day (breakfast through snacks).
public enum MealBucket: String, Sendable, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snacks
}
