import Foundation
import Testing
@testable import Core

@Suite("Workout history formatting")
struct WorkoutHistoryFormattingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("duration label rounds up to at least one minute")
    func durationLabel() {
        let started = date(year: 2025, month: 8, day: 5, hour: 10)
        let ended = started.addingTimeInterval(3_240)
        #expect(WorkoutHistoryFormatting.durationMinutes(startedAt: started, endedAt: ended) == 54)
        #expect(WorkoutHistoryFormatting.durationLabel(startedAt: started, endedAt: ended) == "54 min")
    }

    @Test("duration label formats hours")
    func durationHours() {
        let started = date(year: 2025, month: 8, day: 5, hour: 10)
        let ended = started.addingTimeInterval(4_320)
        #expect(WorkoutHistoryFormatting.durationLabel(startedAt: started, endedAt: ended) == "1h 12m")
    }

    @Test("contextual date uses today and yesterday labels")
    func contextualDate() {
        let now = date(year: 2025, month: 8, day: 5, hour: 18)
        let today = date(year: 2025, month: 8, day: 5, hour: 9)
        let yesterday = date(year: 2025, month: 8, day: 4, hour: 9)

        let todayLabel = WorkoutHistoryFormatting.contextualDateTimeLabel(today, now: now, calendar: calendar)
        let yesterdayLabel = WorkoutHistoryFormatting.contextualDateTimeLabel(yesterday, now: now, calendar: calendar)

        #expect(todayLabel.hasPrefix("Today ·"))
        #expect(yesterdayLabel.hasPrefix("Yesterday ·"))
    }

    @Test("groups sessions by month in newest-first order")
    func groupByMonth() {
        let august = WorkoutSessionSummary(
            id: "aug",
            title: "August",
            startedAt: date(year: 2025, month: 8, day: 12),
            endedAt: date(year: 2025, month: 8, day: 12),
            totalVolumeKilograms: 100,
            totalSetCount: 10,
            totalRepCount: 50,
            exerciseCount: 3
        )
        let july = WorkoutSessionSummary(
            id: "jul",
            title: "July",
            startedAt: date(year: 2025, month: 7, day: 12),
            endedAt: date(year: 2025, month: 7, day: 12),
            totalVolumeKilograms: 100,
            totalSetCount: 10,
            totalRepCount: 50,
            exerciseCount: 3
        )

        let grouped = WorkoutHistoryFormatting.groupByMonth([august, july], calendar: calendar)
        #expect(grouped.count == 2)
        #expect(grouped[0].sessions.map(\.id) == ["aug"])
        #expect(grouped[1].sessions.map(\.id) == ["jul"])
        #expect(grouped[0].title.contains("2025"))
        #expect(grouped[0].title.lowercased().contains("august"))
    }

    @Test("accessibility label includes key metrics")
    func accessibilityLabel() {
        let summary = WorkoutSessionSummary(
            id: "s1",
            title: "Push Day",
            startedAt: date(year: 2025, month: 8, day: 5),
            endedAt: date(year: 2025, month: 8, day: 5).addingTimeInterval(3_240),
            totalVolumeKilograms: 6_420,
            totalSetCount: 16,
            totalRepCount: 80,
            exerciseCount: 5
        )

        let label = WorkoutHistoryFormatting.accessibilityLabel(for: summary)
        #expect(label.contains("Push Day"))
        #expect(label.contains("5 exercises"))
        #expect(label.contains("16 sets"))
    }
}
