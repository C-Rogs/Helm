import Foundation
import Testing
@testable import Core

@Suite("Sleep aggregation")
struct SleepAggregationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(_ components: DateComponents) -> Date {
        calendar.date(from: components)!
    }

    @Test("wake-day window spans 18:00 previous day to 18:00 wake day")
    func sleepWindowBounds() {
        let wakeDay = date(DateComponents(year: 2026, month: 7, day: 24))
        let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
        let windowEnd = SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)

        #expect(calendar.component(.day, from: windowStart) == 23)
        #expect(calendar.component(.hour, from: windowStart) == 18)
        #expect(calendar.component(.day, from: windowEnd) == 24)
        #expect(calendar.component(.hour, from: windowEnd) == 18)
    }

    @Test("fragments split across helmDay buckets sum to full night on wake day")
    func splitBucketNightTotalsWakeDay() {
        let wakeDay = HelmDay(year: 2026, month: 7, day: 24)
        let friday = HelmDay(year: 2026, month: 7, day: 23)

        let preCutoff = SleepRecord(
            start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23, minute: 15)),
            end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 3, minute: 59)),
            helmDay: friday,
            stage: .asleepCore
        )
        let postCutoff = SleepRecord(
            start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 0)),
            end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 7, minute: 5)),
            helmDay: wakeDay,
            stage: .asleepCore
        )

        let allRecords = [preCutoff, postCutoff]
        let wakeTotal = SleepAggregation.totalHours(for: wakeDay, records: allRecords, calendar: calendar)
        let priorTotal = SleepAggregation.totalHours(for: friday, records: allRecords, calendar: calendar)

        #expect(wakeTotal != nil)
        #expect(abs((wakeTotal ?? 0) - 7.833) < 0.05)
        #expect(priorTotal == nil || (priorTotal ?? 0) < 1.0)
    }

    @Test("overlapping intervals merge before summing")
    func overlappingIntervalsMerge() {
        let wakeDay = HelmDay(year: 2026, month: 7, day: 24)
        let overlapping = [
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 6, minute: 0)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepUnspecified
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 1, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 5, minute: 0)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepCore
            ),
        ]

        let total = SleepAggregation.totalHours(for: wakeDay, records: overlapping, calendar: calendar)
        #expect(abs((total ?? 0) - 7.0) < 0.02)
    }

    @Test("night summary matches Apple time asleep with staged samples and WASO")
    func nightSummaryStagesAndEfficiency() {
        let wakeDay = date(DateComponents(year: 2026, month: 7, day: 24))
        let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
        let windowEnd = SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)

        let records = [
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 6, minute: 0)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .inBed
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 33)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepCore
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 2, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 2, minute: 27)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .awake
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 3, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 0)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepDeep
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 33)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepREM
            ),
        ]

        let summary = SleepAggregation.nightSummary(
            from: records,
            windowStart: windowStart,
            windowEnd: windowEnd
        )

        #expect(abs((summary.asleepHours ?? 0) - 5.55) < 0.03)
        #expect(abs((summary.awakeMinutes ?? 0) - 27) < 1)
        #expect(abs((summary.deepMinutes ?? 0) - 60) < 1)
        #expect(abs((summary.remMinutes ?? 0) - 33) < 1)
        #expect(summary.efficiency != nil)
        #expect((summary.efficiency ?? 0) > 0.75)
    }

    @Test("awake and in-bed intervals do not inflate time asleep")
    func nonAsleepStagesExcludedFromDuration() {
        let wakeDay = date(DateComponents(year: 2026, month: 7, day: 24))
        let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
        let windowEnd = SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)

        let records = [
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 7, minute: 0)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .inBed
            ),
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 1, minute: 0)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 1, minute: 30)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .awake
            ),
        ]

        let summary = SleepAggregation.nightSummary(
            from: records,
            windowStart: windowStart,
            windowEnd: windowEnd
        )

        #expect(summary.asleepHours == nil)
        #expect(abs((summary.inBedHours ?? 0) - 8.0) < 0.02)
        #expect(abs((summary.awakeMinutes ?? 0) - 30) < 1)
    }
}
