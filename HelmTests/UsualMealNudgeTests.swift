import Core
import HealthKitIngest
import Persistence
import XCTest
import UserNotifications
@testable import Helm

@MainActor
final class UsualMealNudgeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    func testCooldownIsPerBucketAndExpires() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let beforeCooldown = now.addingTimeInterval(-UsualMealPreferences.nudgeCooldown - 1)

        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: beforeCooldown)
        XCTAssertFalse(UsualMealPreferences.isNudgeCoolingDown(bucket: .lunch, now: now))
        XCTAssertFalse(UsualMealPreferences.isNudgeCoolingDown(bucket: .dinner, now: now))

        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: now)
        XCTAssertTrue(UsualMealPreferences.isNudgeCoolingDown(bucket: .lunch, now: now))
        XCTAssertFalse(
            UsualMealPreferences.isNudgeCoolingDown(
                bucket: .lunch,
                now: now.addingTimeInterval(UsualMealPreferences.nudgeCooldown)
            )
        )

        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: beforeCooldown)
    }

    func testSkipStartsTheSameCooldownUsedByInAppNudges() {
        let day = HelmDay(year: 2026, month: 9, day: 10)
        let now = Date()
        let beforeCooldown = now
            .addingTimeInterval(-UsualMealPreferences.nudgeCooldown - 1)

        UsualMealPreferences.markNudgeOffered(bucket: .dinner, at: beforeCooldown)
        UsualMealPreferences.clearSkip(day: day, bucket: .dinner)
        UsualMealPreferences.skip(day: day, bucket: .dinner)

        XCTAssertTrue(UsualMealPreferences.isSkipped(day: day, bucket: .dinner))
        XCTAssertTrue(UsualMealPreferences.isNudgeCoolingDown(bucket: .dinner, now: now))

        UsualMealPreferences.clearSkip(day: day, bucket: .dinner)
        UsualMealPreferences.markNudgeOffered(bucket: .dinner, at: beforeCooldown)
    }

    func testLoggedBucketRemovesItsPendingReminder() async throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 9, day: 10)
        let meal = MealRecord(
            helmDay: day,
            name: "Lunch",
            loggedAt: date(day: day, hour: 12),
            bucket: .lunch,
            energy: Energy(kilocalories: 500),
            proteinGrams: 25,
            carbohydrateGrams: 50,
            fatGrams: 15,
            source: .manual
        )
        try store.nutrition.upsertMeal(meal)

        let center = NotificationCenterSpy()
        let scheduler = UsualMealNotificationScheduler(
            persistence: store,
            center: center,
            calendar: calendar
        )
        let identifier = UsualMealNotificationPlanner.notificationIdentifier(day: day, bucket: .lunch)
        center.pending = [
            UNNotificationRequest(
                identifier: identifier,
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        ]

        await scheduler.cancelLogged(for: day)

        XCTAssertEqual(center.removedPending, [identifier])
        XCTAssertEqual(center.removedDelivered, [identifier])
    }

    func testInAppStoreHonorsTheSharedCooldown() throws {
        let persistence = try PersistenceStore.inMemory()
        let now = date(day: HelmDay(year: 2026, month: 9, day: 10), hour: 7)
        let targetDay = HelmDay.day(for: now, calendar: calendar)

        for offset in 1 ... UsualMealResolver.minimumSamples {
            let day = targetDay.adding(days: -offset, calendar: calendar)
            try persistence.nutrition.upsertMeal(
                MealRecord(
                    helmDay: day,
                    name: "Usual lunch",
                    loggedAt: date(day: day, hour: 12),
                    bucket: .lunch,
                    energy: Energy(kilocalories: 500),
                    proteinGrams: 25,
                    carbohydrateGrams: 50,
                    fatGrams: 15,
                    source: .manual
                )
            )
        }

        let beforeCooldown = now.addingTimeInterval(-UsualMealPreferences.nudgeCooldown - 1)
        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: beforeCooldown)
        let store = UsualMealStore(persistence: persistence, now: { now })
        store.reload(for: targetDay)
        XCTAssertNotNil(store.proposal(for: .lunch))

        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: now)
        store.reload(for: targetDay)
        XCTAssertNil(store.proposal(for: .lunch))

        UsualMealPreferences.markNudgeOffered(bucket: .lunch, at: beforeCooldown)
    }

    func testOneMatchingDayDoesNotScheduleAUsualReminder() async throws {
        let store = try PersistenceStore.inMemory()
        let now = date(day: HelmDay(year: 2026, month: 9, day: 10), hour: 7)
        let targetDay = HelmDay.day(for: now, calendar: calendar)
        let yesterday = targetDay.adding(days: -1, calendar: calendar)
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: yesterday,
                name: "One-off lunch",
                loggedAt: date(day: yesterday, hour: 12),
                bucket: .lunch,
                energy: Energy(kilocalories: 500),
                proteinGrams: 25,
                carbohydrateGrams: 50,
                fatGrams: 15,
                source: .manual
            )
        )

        UserDefaults.standard.set(true, forKey: "helm.onboarding.completed")
        UserDefaults.standard.set(true, forKey: "helm.usualMeal.nudge")
        UsualMealPreferences.markNudgeOffered(
            bucket: .lunch,
            at: now.addingTimeInterval(-UsualMealPreferences.nudgeCooldown - 1)
        )

        let center = NotificationCenterSpy()
        let scheduler = UsualMealNotificationScheduler(
            persistence: store,
            center: center,
            calendar: calendar
        )
        await scheduler.reschedule(now: now)

        XCTAssertFalse(
            center.added.contains {
                $0.identifier == UsualMealNotificationPlanner.notificationIdentifier(
                    day: targetDay,
                    bucket: .lunch
                )
            }
        )

        UserDefaults.standard.removeObject(forKey: "helm.onboarding.completed")
        UserDefaults.standard.removeObject(forKey: "helm.usualMeal.nudge")
        UsualMealPreferences.markNudgeOffered(
            bucket: .lunch,
            at: now.addingTimeInterval(-UsualMealPreferences.nudgeCooldown - 1)
        )
    }

    private func date(day: HelmDay, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour)
        )!
    }
}

private final class NotificationCenterSpy: @unchecked Sendable, NotificationScheduling {
    var pending: [UNNotificationRequest] = []
    var added: [UNNotificationRequest] = []
    var removedPending: [String] = []
    var removedDelivered: [String] = []

    func add(_ request: UNNotificationRequest) async throws {
        added.append(request)
        pending.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedPending.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllPendingNotificationRequests() async {
        pending.removeAll()
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        removedDelivered.append(contentsOf: identifiers)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pending
    }

    func deliveredNotifications() async -> [UNNotification] {
        []
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}

    func notificationCategories() async -> Set<UNNotificationCategory> {
        []
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        .authorized
    }
}
