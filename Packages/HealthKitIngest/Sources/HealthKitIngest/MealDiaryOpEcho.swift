import Core
import Foundation

/// Verified diary mutation summary for coach post-op echo (CAM-44 / CAM-45).
public enum MealDiaryOpEcho: Sendable {
    public static func deleted(count: Int, day: HelmDay, bucket: MealBucket?) -> String {
        let mealWord = count == 1 ? "meal" : "meals"
        if let bucket {
            return "deleted \(count) \(mealWord) on \(day.formatted) \(bucket.rawValue)"
        }
        return "deleted \(count) \(mealWord) on \(day.formatted)"
    }

    public static func copied(
        count: Int,
        source: HelmDay,
        sourceBucket: MealBucket,
        target: HelmDay,
        targetBucket: MealBucket
    ) -> String {
        let mealWord = count == 1 ? "meal" : "meals"
        return "copied \(count) \(mealWord) from \(source.formatted) \(sourceBucket.rawValue) → \(target.formatted) \(targetBucket.rawValue)"
    }
}
