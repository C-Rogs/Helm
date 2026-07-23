import Core
import Foundation

public enum PostWorkoutNotificationPlanner {
    public static let notificationCategoryID = "helm.post_workout"
    public static let sessionIDUserInfoKey = "session_id"

    public static func notificationIdentifier(sessionID: String) -> String {
        "helm.post_workout.\(sessionID)"
    }

    public static func title() -> String {
        "Session complete"
    }

    public static func body(summary: PostWorkoutSummary) -> String {
        var parts = [
            "\(summary.setCount) sets across \(summary.exerciseCount) exercises in \(summary.durationMinutes) min."
        ]

        if summary.personalRecordCount > 0 {
            let noun = summary.personalRecordCount == 1 ? "PR" : "PRs"
            parts.append("\(summary.personalRecordCount) new \(noun).")
        }

        let text = parts.joined(separator: " ")
        guard text.count > 180 else { return text }
        let prefix = text.prefix(177)
        return "\(prefix)..."
    }
}
