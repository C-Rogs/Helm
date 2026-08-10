import Foundation

public enum WorkoutLiveActivityPolicy {
    public static let baselineRelevanceScore: Double = 75
    public static let elevatedRelevanceScore: Double = 100

    public static func relevanceScore(elevated: Bool) -> Double {
        elevated ? elevatedRelevanceScore : baselineRelevanceScore
    }
}
