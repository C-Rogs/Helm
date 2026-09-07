import Foundation
import Testing
@testable import Core

@Suite("Weekly check-in preferences")
struct WeeklyCheckInPreferencesTests {
    @Test("defaults to Sunday when unset")
    func defaultWeekday() {
        let suite = "helm.tests.checkIn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(WeeklyCheckInPreferences.checkInWeekday(defaults: defaults) == 1)
    }

    @Test("persists check-in weekday")
    func persistsWeekday() {
        let suite = "helm.tests.checkIn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        WeeklyCheckInPreferences.setCheckInWeekday(2, defaults: defaults)
        #expect(WeeklyCheckInPreferences.checkInWeekday(defaults: defaults) == 2)
    }

    @Test("clamps invalid weekday to Sunday")
    func clampsInvalid() {
        let suite = "helm.tests.checkIn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        WeeklyCheckInPreferences.setCheckInWeekday(0, defaults: defaults)
        #expect(WeeklyCheckInPreferences.checkInWeekday(defaults: defaults) == 1)
        defaults.set(99, forKey: WeeklyCheckInPreferences.checkInWeekdayKey)
        #expect(WeeklyCheckInPreferences.checkInWeekday(defaults: defaults) == 7)
    }

    @Test("due only on check-in weekday before Got it")
    func dueLogic() {
        let suite = "helm.tests.checkIn.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-09-06 is Sunday (weekday 1)
        let sunday = HelmDay(year: 2026, month: 9, day: 6)
        let monday = HelmDay(year: 2026, month: 9, day: 7)

        WeeklyCheckInPreferences.setCheckInWeekday(1, defaults: defaults)
        #expect(
            WeeklyCheckInPreferences.isTrainingReviewDue(
                today: sunday, calendar: calendar, defaults: defaults
            )
        )
        #expect(
            !WeeklyCheckInPreferences.isTrainingReviewDue(
                today: monday, calendar: calendar, defaults: defaults
            )
        )

        WeeklyCheckInPreferences.recordTrainingReview(on: sunday, defaults: defaults)
        #expect(
            !WeeklyCheckInPreferences.isTrainingReviewDue(
                today: sunday, calendar: calendar, defaults: defaults
            )
        )
    }
}
