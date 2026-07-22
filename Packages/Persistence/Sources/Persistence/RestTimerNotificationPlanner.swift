import Foundation

public enum RestTimerNotificationPlanner {
    public static let notificationCategoryID = "helm.rest_timer"
    public static let sessionIDKey = "sessionID"
    public static let timerIDKey = "timerID"

    public static func notificationIdentifier(sessionID: String) -> String {
        "helm.rest.\(sessionID)"
    }

    public static func shouldScheduleRestEndNotification(endsAt: Date, now: Date) -> Bool {
        endsAt > now
    }

    public static func restEndFireInterval(endsAt: Date, now: Date) -> TimeInterval? {
        let interval = endsAt.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return interval
    }
}
