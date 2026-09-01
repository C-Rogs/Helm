import Core
import Foundation
import HealthKitIngest
import UserNotifications

private let usualMealPendingOtherDayKey = "helm.pendingUsualMealOther.day"
private let usualMealPendingOtherBucketKey = "helm.pendingUsualMealOther.bucket"
private let usualMealPendingOtherSearchKey = "helm.pendingUsualMealOther.search"

@MainActor
enum UsualMealNotificationRouter {
    nonisolated static func storePendingOther(day: HelmDay, bucket: MealBucket, startSearch: Bool) {
        UserDefaults.standard.set(day.formatted, forKey: usualMealPendingOtherDayKey)
        UserDefaults.standard.set(bucket.rawValue, forKey: usualMealPendingOtherBucketKey)
        UserDefaults.standard.set(startSearch, forKey: usualMealPendingOtherSearchKey)
    }

    nonisolated static func consumePendingOther() -> (day: HelmDay, bucket: MealBucket, startSearch: Bool)? {
        guard
            let dayRaw = UserDefaults.standard.string(forKey: usualMealPendingOtherDayKey),
            let bucketRaw = UserDefaults.standard.string(forKey: usualMealPendingOtherBucketKey),
            let bucket = MealBucket(rawValue: bucketRaw)
        else {
            return nil
        }
        let startSearch = UserDefaults.standard.bool(forKey: usualMealPendingOtherSearchKey)
        UserDefaults.standard.removeObject(forKey: usualMealPendingOtherDayKey)
        UserDefaults.standard.removeObject(forKey: usualMealPendingOtherBucketKey)
        UserDefaults.standard.removeObject(forKey: usualMealPendingOtherSearchKey)
        let parts = dayRaw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let dayValue = Int(parts[2]) else {
            return nil
        }
        return (HelmDay(year: year, month: month, day: dayValue), bucket, startSearch)
    }

    static func handle(
        actionIdentifier: String,
        helmDayRaw: String?,
        bucketRaw: String?
    ) async {
        let bucket = bucketRaw.flatMap(MealBucket.init(rawValue:)) ?? .breakfast
        let day = helmDayRaw.flatMap(UsualMealNotificationPlanner.parseHelmDay)
            ?? HelmDay.day(for: Date(), calendar: .current)

        switch actionIdentifier {
        case UsualMealNotificationPlanner.yesActionID:
            UsualMealPreferences.clearSkip(day: day, bucket: bucket)
            _ = await UsualMealIntentBootstrap.log(bucket: bucket, helmDay: day)
        case UsualMealNotificationPlanner.skipActionID:
            UsualMealPreferences.skip(day: day, bucket: bucket)
            await NutritionBootstrap.usualMealScheduler.cancel(day: day, bucket: bucket)
        case UsualMealNotificationPlanner.otherActionID:
            storePendingOther(day: day, bucket: bucket, startSearch: true)
            await processPendingIfForeground()
        case UNNotificationDefaultActionIdentifier:
            storePendingOther(day: day, bucket: bucket, startSearch: false)
            await processPendingIfForeground()
        default:
            break
        }
    }

    static func processPendingIfForeground() async {
        guard AppLifecycleState.isForeground else { return }
        guard let pending = consumePendingOther() else { return }
        AppTabRouter.shared.openNutrition(
            focus: NutritionNavigationFocus(
                helmDay: pending.day,
                bucket: pending.bucket,
                startSearch: pending.startSearch
            )
        )
    }
}
