import CoachLLM
import Core
import Foundation

public enum MealCopyCommandApplier {
    public static func preview(
        for payload: MealCopyPayload,
        today: HelmDay,
        calendar: Calendar = .current
    ) -> (title: String, detail: String) {
        guard let resolved = resolvedDays(payload, today: today, calendar: calendar) else {
            let sourceBucket = MealBucket(rawValue: payload.sourceBucket.lowercased())?.displayName
                ?? payload.sourceBucket.capitalized
            return (
                title: "Copy \(sourceBucket.lowercased())",
                detail: "Choose a valid source and target day."
            )
        }
        let sourceBucket = resolved.sourceBucket.displayName
        let targetBucket = resolved.targetBucket.displayName
        return (
            title: "Copy \(sourceBucket.lowercased())",
            detail: "\(resolved.source.formatted) \(sourceBucket.lowercased()) → \(resolved.target.formatted) \(targetBucket.lowercased())"
        )
    }

    public static func resolvedDays(
        _ payload: MealCopyPayload,
        today: HelmDay,
        calendar: Calendar = .current
    ) -> (source: HelmDay, target: HelmDay, sourceBucket: MealBucket, targetBucket: MealBucket)? {
        guard let source = parseDay(payload.sourceHelmDay),
              let sourceBucket = MealBucket(rawValue: payload.sourceBucket.lowercased()) else {
            return nil
        }
        let target = parseDay(payload.targetHelmDay) ?? today
        let targetBucket = MealBucket(rawValue: payload.targetBucket.lowercased()) ?? sourceBucket
        return (source, target, sourceBucket, targetBucket)
    }

    /// Backward-compatible resolver without an explicit calendar day (uses `today`).
    public static func resolvedDays(
        _ payload: MealCopyPayload
    ) -> (source: HelmDay, target: HelmDay, sourceBucket: MealBucket, targetBucket: MealBucket)? {
        let today = HelmDay.day(for: Date(), calendar: .current)
        return resolvedDays(payload, today: today)
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
