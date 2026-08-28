import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Coach chat chart builder")
struct CoachChatChartBuilderTests {
    @Test("weekly calories chart uses diary totals for the Monday week")
    func weeklyCaloriesFromDiary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let friday = HelmDay(year: 2026, month: 8, day: 28)
        let store = try PersistenceStore.inMemory()
        try store.nutrition.upsertDay(
            NutritionDay(
                helmDay: HelmDay(year: 2026, month: 8, day: 24),
                totalEnergy: Energy(kilocalories: 2100)
            )
        )
        try store.nutrition.upsertDay(
            NutritionDay(
                helmDay: HelmDay(year: 2026, month: 8, day: 28),
                totalEnergy: Energy(kilocalories: 1800)
            )
        )

        let chart = try CoachChatChartBuilder.build(
            kind: .weeklyCalories,
            store: store,
            endingAt: friday,
            calendar: calendar
        )

        #expect(chart.points.count == 7)
        #expect(chart.points.first?.label == "Mon")
        #expect(chart.points.first?.value == 2100)
        #expect(chart.points.last?.label == "Sun")
        let fridayPoint = chart.points.first { $0.label == "Fri" }
        #expect(fridayPoint?.value == 1800)
        #expect(ChartPayloadParser.parse(from: ChartPayloadParser.persistText(reply: chart.reply, payload: chart)) != nil)
    }
}
