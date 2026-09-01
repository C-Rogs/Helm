import Core
import Foundation

public enum UsualMealNotificationPlanner {
    public static let notificationCategoryID = "helm.usual_meal"
    public static let yesActionID = "helm.usual_meal.yes"
    public static let skipActionID = "helm.usual_meal.skip"
    public static let otherActionID = "helm.usual_meal.other"
    public static let helmDayUserInfoKey = "helm_day"
    public static let bucketUserInfoKey = "bucket"
    public static let identifierPrefix = "helm.usual_meal."

    public static func notificationIdentifier(day: HelmDay, bucket: MealBucket) -> String {
        "\(identifierPrefix)\(day.formatted).\(bucket.rawValue)"
    }

    public static func isUsualMeal(categoryIdentifier: String) -> Bool {
        categoryIdentifier == notificationCategoryID
    }

    public static func title(proposal: UsualMealProposal) -> String {
        proposal.prompt
    }

    public static func body(proposal: UsualMealProposal) -> String {
        "\(proposal.energyKcal) kcal. Yes logs it."
    }

    public static func userInfo(day: HelmDay, bucket: MealBucket) -> [String: String] {
        [
            helmDayUserInfoKey: day.formatted,
            bucketUserInfoKey: bucket.rawValue
        ]
    }

    public static func bucket(fromUserInfo userInfo: [AnyHashable: Any]) -> MealBucket? {
        guard let raw = userInfo[bucketUserInfoKey] as? String else { return nil }
        return MealBucket(rawValue: raw)
    }

    public static func helmDay(fromUserInfo userInfo: [AnyHashable: Any]) -> HelmDay? {
        guard let raw = userInfo[helmDayUserInfoKey] as? String else { return nil }
        return parseHelmDay(raw)
    }

    public static func parseHelmDay(_ raw: String) -> HelmDay? {
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
