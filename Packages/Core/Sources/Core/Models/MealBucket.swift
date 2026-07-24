import Foundation

/// Meal slot within a logical day (breakfast through snacks).
public enum MealBucket: String, Sendable, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snacks

    public var displayName: String {
        switch self {
        case .breakfast:
            "Breakfast"
        case .lunch:
            "Lunch"
        case .dinner:
            "Dinner"
        case .snacks:
            "Snacks"
        }
    }
}
