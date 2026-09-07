import Core
import Foundation
import NutritionKit

public final class NutritionPreferencesStore: @unchecked Sendable {
    public static let dietarySourceModeKey = "helm.nutrition.dietarySourceMode"
    public static let checkInWeekdayKey = WeeklyCheckInPreferences.checkInWeekdayKey
    public static let lastCheckInCompletedOnKey = "helm.nutrition.lastCheckInCompletedOn"
    public static let shared = NutritionPreferencesStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func mode() -> DietarySourceMode {
        lock.withLock {
            guard
                let raw = defaults.string(forKey: Self.dietarySourceModeKey),
                let stored = DietarySourceMode(rawValue: raw)
            else {
                return .mergeExternal
            }
            return stored
        }
    }

    public func setMode(_ mode: DietarySourceMode) {
        lock.withLock {
            defaults.set(mode.rawValue, forKey: Self.dietarySourceModeKey)
        }
    }

    /// Calendar weekday 1…7 (Sunday…Saturday). Defaults to Sunday.
    /// Shared with training week review via `WeeklyCheckInPreferences`.
    public func checkInWeekday() -> Int {
        lock.withLock {
            WeeklyCheckInPreferences.checkInWeekday(defaults: defaults)
        }
    }

    public func setCheckInWeekday(_ weekday: Int) {
        lock.withLock {
            WeeklyCheckInPreferences.setCheckInWeekday(weekday, defaults: defaults)
        }
    }

    public func lastCheckInCompletedOn() -> HelmDay? {
        lock.withLock {
            guard let raw = defaults.string(forKey: Self.lastCheckInCompletedOnKey) else { return nil }
            return Self.parseHelmDay(raw)
        }
    }

    public func setLastCheckInCompletedOn(_ day: HelmDay?) {
        lock.withLock {
            if let day {
                defaults.set(day.formatted, forKey: Self.lastCheckInCompletedOnKey)
            } else {
                defaults.removeObject(forKey: Self.lastCheckInCompletedOnKey)
            }
        }
    }

    public func isCheckInDue(today: HelmDay, calendar: Calendar = .current) -> Bool {
        guard let date = calendar.date(from: today.dateComponents()) else { return false }
        let weekday = calendar.component(.weekday, from: date)
        return NutritionWeeklyCheckIn.isDue(
            today: today,
            todayWeekday: weekday,
            preferredWeekday: checkInWeekday(),
            lastCompletedOn: lastCheckInCompletedOn()
        )
    }

    private static func parseHelmDay(_ raw: String) -> HelmDay? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
