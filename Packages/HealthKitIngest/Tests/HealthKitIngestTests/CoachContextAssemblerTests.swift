import CoachLLM
import Core
import Foundation
import Persistence
import ReadinessKit
import Testing
@testable import HealthKitIngest

@Suite("CoachContextAssembler")
struct CoachContextAssemblerTests {
    private let day = HelmDay(year: 2026, month: 7, day: 22)
    private let previous = HelmDay(year: 2026, month: 7, day: 21)

    @Test("assembles recent days from persisted health rows")
    func assemblesRecentDays() throws {
        let store = try PersistenceStore.inMemory()

        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: previous,
                hrvSDNN: DurationMs(milliseconds: 49),
                restingHeartRate: 52,
                priorDayTRIMP: 42
            )
        )
        try store.readiness.upsertScore(
            helmDay: previous,
            scoreJSON: """
            {"score":58,"effectiveHRVMilliseconds":49.0,"restingHeartRate":52}
            """
        )
        try store.readiness.upsertBaseline(
            stateJSON: """
            {"hrvChronic":{"mean":52.1,"robustSigma":4.0},"restingHR":{"mean":51.0,"robustSigma":2.0},"seededNightCount":28}
            """
        )

        let context = try CoachContextAssembler.assemble(from: store, endingAt: day, lookbackDays: 7)

        #expect(context.readinessBaselines.contains("hrvChronicMs=52.1"))
        #expect(context.readinessBaselines.contains("seededNights=28"))
        #expect(context.recent.count == 1)
        #expect(context.recent[0].helmDay == previous)
        #expect(context.recent[0].text.contains("readiness=58"))
        #expect(context.recent[0].text.contains("hrv=49ms"))
        #expect(context.recent[0].text.contains("trimp=42"))
    }
}
