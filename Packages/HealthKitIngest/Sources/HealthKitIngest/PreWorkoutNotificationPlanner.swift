import Core
import Foundation

public enum PreWorkoutNotificationPlanner {
    public static let notificationCategoryID = "helm.pre_workout"
    public static let helmDayUserInfoKey = "helm_day"

    public static func notificationIdentifier(for day: HelmDay) -> String {
        "helm.pre_workout.\(day.formatted)"
    }

    public static func title() -> String {
        "Pre-workout prime"
    }

    public static func body(
        summary: PrescribedSessionSummary,
        readinessScore: Int?
    ) -> String {
        var parts: [String] = [
            "\(summary.title) · \(summary.totalSets) sets · \(summary.exercises.count) exercises"
        ]

        if summary.readinessAdjusted {
            parts.append("volume trimmed for readiness")
        }

        if let readinessScore {
            parts.append("ARC \(readinessScore)")
        }

        if let emphasis = summary.emphasis, !emphasis.isEmpty {
            parts.append(emphasis)
        }

        let text = parts.joined(separator: " · ")
        guard text.count > 180 else { return text }
        let prefix = text.prefix(177)
        return "\(prefix)..."
    }
}
