import Foundation

public enum RestNotificationLaunchPayload {
    public static func sessionID(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        userInfo[RestTimerNotificationPlanner.sessionIDKey] as? String
    }

    public static func isRestTimerNotification(categoryIdentifier: String) -> Bool {
        categoryIdentifier == RestTimerNotificationPlanner.notificationCategoryID
    }
}
