import Foundation
import Testing
@testable import Persistence

@Suite("Rest timer notification planner")
struct RestTimerNotificationPlannerTests {
    @Test("schedules when rest end is in the future")
    func schedulesFutureRest() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(90)
        #expect(RestTimerNotificationPlanner.shouldScheduleRestEndNotification(endsAt: endsAt, now: now))
        #expect(RestTimerNotificationPlanner.restEndFireInterval(endsAt: endsAt, now: now) == 90)
    }

    @Test("skips when rest already ended")
    func skipsExpiredRest() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let endsAt = now.addingTimeInterval(-1)
        #expect(!RestTimerNotificationPlanner.shouldScheduleRestEndNotification(endsAt: endsAt, now: now))
        #expect(RestTimerNotificationPlanner.restEndFireInterval(endsAt: endsAt, now: now) == nil)
    }

    @Test("notification identifier is stable per session")
    func stableIdentifier() {
        #expect(
            RestTimerNotificationPlanner.notificationIdentifier(sessionID: "abc")
                == "helm.rest.abc"
        )
    }
}
