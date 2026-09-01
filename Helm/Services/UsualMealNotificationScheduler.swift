import Core
import Foundation
import HealthKitIngest
import Persistence
import UserNotifications

@MainActor
final class UsualMealNotificationScheduler {
    private let center: any NotificationScheduling
    private let persistence: PersistenceStore
    private let calendar: Calendar

    init(
        persistence: PersistenceStore,
        center: any NotificationScheduling = LiveNotificationCenter(),
        calendar: Calendar = .current
    ) {
        self.persistence = persistence
        self.center = center
        self.calendar = calendar
    }

    func registerCategories() async {
        let yes = UNNotificationAction(
            identifier: UsualMealNotificationPlanner.yesActionID,
            title: "Yes",
            options: []
        )
        let skip = UNNotificationAction(
            identifier: UsualMealNotificationPlanner.skipActionID,
            title: "Not today",
            options: []
        )
        let other = UNNotificationAction(
            identifier: UsualMealNotificationPlanner.otherActionID,
            title: "Something else",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: UsualMealNotificationPlanner.notificationCategoryID,
            actions: [yes, skip, other],
            intentIdentifiers: [],
            options: []
        )
        var categories = await center.notificationCategories()
        categories = Set(categories.filter { $0.identifier != UsualMealNotificationPlanner.notificationCategoryID })
        categories.insert(category)
        center.setNotificationCategories(categories)
    }

    func reschedule(now: Date = .now) async {
        guard UsualMealPreferences.nudgeEnabled else {
            await cancelAll()
            return
        }
        guard !FestivalModePreferences.shared.isFestivalModeEnabled else {
            await cancelAll()
            return
        }
        guard UserDefaults.standard.bool(forKey: OnboardingStore.completedDefaultsKey) else {
            await cancelAll()
            return
        }

        await registerCategories()

        let day = HelmDay.day(for: now, calendar: calendar)
        let resolver = UsualMealResolver(store: persistence, calendar: calendar)
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()

        for bucket in MealBucket.allCases {
            let identifier = UsualMealNotificationPlanner.notificationIdentifier(day: day, bucket: bucket)
            guard !UsualMealPreferences.isSkipped(day: day, bucket: bucket) else {
                await cancel(identifier: identifier)
                continue
            }
            let samples = (try? resolver.matchingSamples(for: bucket, on: day)) ?? []
            guard !samples.isEmpty else {
                await cancel(identifier: identifier)
                continue
            }
            guard let proposal = try? resolver.proposal(for: bucket, on: day, samples: samples) else {
                await cancel(identifier: identifier)
                continue
            }
            if delivered.contains(where: { $0.request.identifier == identifier }) {
                continue
            }
            let loggedAts = samples.flatMap { $0.meals.map(\.loggedAt) }
            guard let fireDate = UsualMealFirePlanner.fireDate(
                day: day,
                bucket: bucket,
                sampleLoggedAts: loggedAts,
                now: now,
                calendar: calendar
            ), let interval = UsualMealFirePlanner.fireInterval(fireDate: fireDate, now: now) else {
                await cancel(identifier: identifier)
                continue
            }
            if pending.contains(where: { $0.identifier == identifier }) {
                await cancel(identifier: identifier)
            }

            let content = UNMutableNotificationContent()
            content.title = UsualMealNotificationPlanner.title(proposal: proposal)
            content.body = UsualMealNotificationPlanner.body(proposal: proposal)
            content.sound = .default
            content.categoryIdentifier = UsualMealNotificationPlanner.notificationCategoryID
            content.userInfo = UsualMealNotificationPlanner.userInfo(day: day, bucket: bucket)

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(UsualMealNotificationPlanner.identifierPrefix) }
        if !identifiers.isEmpty {
            await center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        let delivered = await center.deliveredNotifications()
        let deliveredIDs = delivered
            .map(\.request.identifier)
            .filter { $0.hasPrefix(UsualMealNotificationPlanner.identifierPrefix) }
        if !deliveredIDs.isEmpty {
            await center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        }
    }

    func cancel(day: HelmDay, bucket: MealBucket) async {
        await cancel(identifier: UsualMealNotificationPlanner.notificationIdentifier(day: day, bucket: bucket))
    }

    func cancelPending(for day: HelmDay) async {
        let identifiers = MealBucket.allCases.map {
            UsualMealNotificationPlanner.notificationIdentifier(day: day, bucket: $0)
        }
        await center.removePendingNotificationRequests(withIdentifiers: identifiers)
        await center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func cancel(identifier: String) async {
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
        await center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
