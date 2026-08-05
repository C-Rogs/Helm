import Persistence
import UIKit

enum RestNotificationLaunchOptions {
    @MainActor
    static func pendingSessionID(from launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> String? {
        guard let launchOptions else { return nil }

        if let notification = launchOptions[.localNotification] as? UILocalNotification,
           let sessionID = RestNotificationLaunchPayload.sessionID(fromUserInfo: notification.userInfo ?? [:]) {
            return sessionID
        }

        if let userInfo = launchOptions[.localNotification] as? [AnyHashable: Any],
           let sessionID = RestNotificationLaunchPayload.sessionID(fromUserInfo: userInfo) {
            return sessionID
        }

        if let userInfo = launchOptions[.remoteNotification] as? [AnyHashable: Any],
           let sessionID = RestNotificationLaunchPayload.sessionID(fromUserInfo: userInfo) {
            return sessionID
        }

        return nil
    }
}
