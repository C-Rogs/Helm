import Foundation

/// Live app chrome Coach should know: selected tab and whether a session is running.
/// Rides on the transcript freshness suffix so the cached context block stays stable.
public struct CoachAppSurfaceSnapshot: Sendable, Equatable {
    public let selectedTab: String
    public let sessionStatus: String
    public let sessionTitle: String?
    public let viewedNutritionDay: String?
    public let sessionHelmDay: String?
    public let sessionStale: Bool

    public init(
        selectedTab: String,
        sessionStatus: String,
        sessionTitle: String? = nil,
        viewedNutritionDay: String? = nil,
        sessionHelmDay: String? = nil,
        sessionStale: Bool = false
    ) {
        self.selectedTab = selectedTab
        self.sessionStatus = sessionStatus
        self.sessionTitle = sessionTitle
        self.viewedNutritionDay = viewedNutritionDay
        self.sessionHelmDay = sessionHelmDay
        self.sessionStale = sessionStale
    }

    public var contextText: String {
        var lines = [
            "# App State",
            "tab=\(selectedTab)",
            "session=\(sessionStatus)"
        ]
        if let sessionTitle, !sessionTitle.isEmpty {
            lines.append("session_title=\(sessionTitle)")
        }
        if let sessionHelmDay, !sessionHelmDay.isEmpty {
            lines.append("session_helm_day=\(sessionHelmDay)")
        }
        if sessionStale {
            lines.append("session_stale=true")
        }
        if let viewedNutritionDay, !viewedNutritionDay.isEmpty {
            lines.append("nutrition_day=\(viewedNutritionDay)")
        }
        return lines.joined(separator: "\n")
    }
}
