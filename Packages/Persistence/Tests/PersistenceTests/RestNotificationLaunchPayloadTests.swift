import Testing
@testable import Persistence

@Suite("Rest notification launch payload")
struct RestNotificationLaunchPayloadTests {
    @Test("extracts session id from user info")
    func sessionIDFromUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            RestTimerNotificationPlanner.sessionIDKey: "session-123",
            RestTimerNotificationPlanner.timerIDKey: "timer-456"
        ]
        #expect(RestNotificationLaunchPayload.sessionID(fromUserInfo: userInfo) == "session-123")
    }

    @Test("returns nil when session id missing")
    func missingSessionID() {
        #expect(RestNotificationLaunchPayload.sessionID(fromUserInfo: [:]) == nil)
    }

    @Test("identifies rest timer notification category")
    func restTimerCategory() {
        #expect(
            RestNotificationLaunchPayload.isRestTimerNotification(
                categoryIdentifier: RestTimerNotificationPlanner.notificationCategoryID
            )
        )
        #expect(!RestNotificationLaunchPayload.isRestTimerNotification(categoryIdentifier: "other"))
    }
}
