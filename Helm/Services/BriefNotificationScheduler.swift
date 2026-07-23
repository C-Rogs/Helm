import Core
import Foundation
import HealthKitIngest
import UserNotifications

struct LiveBriefNotificationPoster: BriefNotificationPosting {
    private let center: any NotificationScheduling

    init(center: any NotificationScheduling = LiveNotificationCenter()) {
        self.center = center
    }

    func postMorningBrief(_ brief: StoredDailyBrief) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = BriefNotificationPlanner.title(for: brief)
        content.body = BriefNotificationPlanner.body(for: brief)
        content.sound = .default
        content.categoryIdentifier = BriefNotificationPlanner.notificationCategoryID
        content.userInfo = [
            BriefNotificationPlanner.helmDayUserInfoKey: brief.helmDay.formatted
        ]

        let identifier = BriefNotificationPlanner.notificationIdentifier(for: brief.helmDay)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
