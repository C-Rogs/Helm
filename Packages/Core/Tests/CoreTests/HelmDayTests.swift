import Foundation
import Testing
@testable import Core

@Suite("HelmDay boundary")
struct HelmDayTests {
    private let cutoff = DayCutoff.default

    private func calendar(
        timeZone: TimeZone,
        locale: Locale = Locale(identifier: "en_GB_POSIX")
    ) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    private func date(_ components: DateComponents, calendar: Calendar) -> Date {
        calendar.date(from: components)!
    }

    @Test("times before cutoff belong to previous logical day")
    func beforeCutoff() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let saturday330 = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 3, minute: 30),
            calendar: london
        )

        let helmDay = HelmDay.day(for: saturday330, cutoff: cutoff, calendar: london)

        #expect(helmDay == HelmDay(year: 2026, month: 3, day: 13))
    }

    @Test("times at or after cutoff belong to same calendar day")
    func atAndAfterCutoff() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let saturday400 = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 4, minute: 0),
            calendar: london
        )
        let saturday2300 = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 23, minute: 0),
            calendar: london
        )

        #expect(HelmDay.day(for: saturday400, cutoff: cutoff, calendar: london).formatted == "2026-03-14")
        #expect(HelmDay.day(for: saturday2300, cutoff: cutoff, calendar: london).formatted == "2026-03-14")
    }

    @Test("late-night intake after a party stays on the prior logical day")
    func nightCrossingCutoff() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let fridayNight = date(
            DateComponents(year: 2026, month: 3, day: 13, hour: 23, minute: 45),
            calendar: london
        )
        let saturdayEarly = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 2, minute: 15),
            calendar: london
        )
        let saturdayAfterCutoff = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 4, minute: 30),
            calendar: london
        )

        let friday = HelmDay(year: 2026, month: 3, day: 13)

        #expect(HelmDay.day(for: fridayNight, cutoff: cutoff, calendar: london) == friday)
        #expect(HelmDay.day(for: saturdayEarly, cutoff: cutoff, calendar: london) == friday)
        #expect(HelmDay.day(for: saturdayAfterCutoff, cutoff: cutoff, calendar: london) != friday)
    }

    @Test("split sleep segments attribute to onset day, not sample end")
    func splitSleep() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let recoveryDay = HelmDay(year: 2026, month: 3, day: 13)

        let firstSegmentStart = date(
            DateComponents(year: 2026, month: 3, day: 13, hour: 23, minute: 30),
            calendar: london
        )
        let firstSegmentEnd = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 1, minute: 15),
            calendar: london
        )
        let secondSegmentStart = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 1, minute: 45),
            calendar: london
        )
        let secondSegmentEnd = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 6, minute: 30),
            calendar: london
        )

        let first = SleepRecord(
            start: firstSegmentStart,
            end: firstSegmentEnd,
            helmDay: SleepRecord.helmDay(forStart: firstSegmentStart, cutoff: cutoff, calendar: london)
        )
        let second = SleepRecord(
            start: secondSegmentStart,
            end: secondSegmentEnd,
            helmDay: SleepRecord.helmDay(forStart: secondSegmentStart, cutoff: cutoff, calendar: london)
        )

        #expect(first.helmDay == recoveryDay)
        #expect(second.helmDay == recoveryDay)
        #expect(HelmDay.day(for: secondSegmentEnd, cutoff: cutoff, calendar: london) != recoveryDay)
    }

    @Test("spring-forward DST keeps cutoff-aligned day boundaries stable")
    func springDST() {
        let newYork = calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        // US spring forward: 2026-03-08 02:00 -> 03:00
        let beforeCutoff = date(
            DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30),
            calendar: newYork
        )
        let afterCutoff = date(
            DateComponents(year: 2026, month: 3, day: 8, hour: 4, minute: 30),
            calendar: newYork
        )

        #expect(HelmDay.day(for: beforeCutoff, cutoff: cutoff, calendar: newYork).formatted == "2026-03-07")
        #expect(HelmDay.day(for: afterCutoff, cutoff: cutoff, calendar: newYork).formatted == "2026-03-08")
    }

    @Test("fall-back DST keeps cutoff-aligned day boundaries stable")
    func fallDST() {
        let newYork = calendar(timeZone: TimeZone(identifier: "America/New_York")!)
        // US fall back: 2026-11-01 02:00 -> 01:00. Use unambiguous instants after the repeated hour.
        let beforeCutoff = date(
            DateComponents(year: 2026, month: 11, day: 1, hour: 3, minute: 30),
            calendar: newYork
        )
        let afterCutoff = date(
            DateComponents(year: 2026, month: 11, day: 1, hour: 4, minute: 30),
            calendar: newYork
        )

        #expect(HelmDay.day(for: beforeCutoff, cutoff: cutoff, calendar: newYork).formatted == "2026-10-31")
        #expect(HelmDay.day(for: afterCutoff, cutoff: cutoff, calendar: newYork).formatted == "2026-11-01")
    }

    @Test("timezone travel maps the same absolute instant to different logical days")
    func timezoneTravel() {
        let instant = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 00:00:00 UTC
        let utc = calendar(timeZone: TimeZone(secondsFromGMT: 0)!)
        let tokyo = calendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)

        let utcDay = HelmDay.day(for: instant, cutoff: cutoff, calendar: utc)
        let tokyoDay = HelmDay.day(for: instant, cutoff: cutoff, calendar: tokyo)

        #expect(utcDay != tokyoDay)
    }

    @Test("custom cutoff shifts the boundary")
    func customCutoff() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let noonCutoff = DayCutoff(hour: 12, minute: 0)
        let morning = date(
            DateComponents(year: 2026, month: 6, day: 10, hour: 11, minute: 59),
            calendar: london
        )
        let afternoon = date(
            DateComponents(year: 2026, month: 6, day: 10, hour: 12, minute: 0),
            calendar: london
        )

        #expect(HelmDay.day(for: morning, cutoff: noonCutoff, calendar: london).formatted == "2026-06-09")
        #expect(HelmDay.day(for: afternoon, cutoff: noonCutoff, calendar: london).formatted == "2026-06-10")
    }

    @Test("logical day interval contains instants across midnight")
    func intervalContains() {
        let london = calendar(timeZone: TimeZone(identifier: "Europe/London")!)
        let day = HelmDay(year: 2026, month: 3, day: 13)
        let lateNight = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 1, minute: 0),
            calendar: london
        )
        let afterCutoff = date(
            DateComponents(year: 2026, month: 3, day: 14, hour: 4, minute: 1),
            calendar: london
        )

        #expect(day.contains(lateNight, cutoff: cutoff, calendar: london))
        #expect(!day.contains(afterCutoff, cutoff: cutoff, calendar: london))
    }
}

@Suite("Units")
struct UnitsTests {
    @Test("energy converts between kcal and kJ")
    func energyConversion() {
        let fromKcal = Energy(kilocalories: 100)
        #expect(abs(fromKcal.kilojoules - 418.4) < 0.001)

        let fromKJ = Energy(kilojoules: 418.4)
        #expect(abs(fromKJ.kilocalories - 100) < 0.001)
    }

    @Test("mass converts between kg and lb")
    func massConversion() {
        let fromKg = Mass(kilograms: 80)
        #expect(abs(fromKg.pounds - 176.37) < 0.1)

        let fromLb = Mass(pounds: 176.37)
        #expect(abs(fromLb.kilograms - 80) < 0.1)
    }

    @Test("duration stores milliseconds explicitly")
    func durationMs() {
        let hrv = DurationMs(milliseconds: 42)
        #expect(hrv.milliseconds == 42)
        #expect(hrv.seconds == 0.042)
    }
}

@Suite("Clock")
struct ClockTests {
    @Test("fixed clock returns configured instant")
    func fixedClock() {
        let instant = Date(timeIntervalSince1970: 1_000)
        let clock = FixedClock(instant: instant)
        #expect(clock.now() == instant)
    }
}
