import CoachLLM
import Core
import Foundation

public enum MealCopyCommandApplier {
    public static func preview(for payload: MealCopyPayload) -> (title: String, detail: String) {
        let sourceBucket = MealBucket(rawValue: payload.sourceBucket.lowercased())?.displayName
            ?? payload.sourceBucket.capitalized
        let targetBucket = MealBucket(rawValue: payload.targetBucket.lowercased())?.displayName
            ?? payload.targetBucket.capitalized
        return (
            title: "Copy \(sourceBucket.lowercased())",
            detail: "\(payload.sourceHelmDay) → \(payload.targetHelmDay) \(targetBucket.lowercased())"
        )
    }

    public static func resolvedDays(
        _ payload: MealCopyPayload
    ) -> (source: HelmDay, target: HelmDay, sourceBucket: MealBucket, targetBucket: MealBucket)? {
        guard let source = parseDay(payload.sourceHelmDay),
              let target = parseDay(payload.targetHelmDay),
              let sourceBucket = MealBucket(rawValue: payload.sourceBucket.lowercased()),
              let targetBucket = MealBucket(rawValue: payload.targetBucket.lowercased()) else {
            return nil
        }
        return (source, target, sourceBucket, targetBucket)
    }

    private static func parseDay(_ raw: String) -> HelmDay? {
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
