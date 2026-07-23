import Core
import Foundation

public enum BriefNotificationPlanner {
    public static let notificationCategoryID = "helm.morning_brief"
    public static let helmDayUserInfoKey = "helm_day"

    public static func notificationIdentifier(for day: HelmDay) -> String {
        "helm.morning_brief.\(day.formatted)"
    }

    public static func title(for brief: StoredDailyBrief) -> String {
        "Morning brief"
    }

    public static func body(for brief: StoredDailyBrief) -> String {
        let text = brief.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "Your readiness brief is ready in Helm."
        }
        if text.count <= 180 {
            return text
        }
        let prefix = text.prefix(177)
        return "\(prefix)..."
    }
}
