import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("RecoveryHistoryQuery")
struct RecoveryHistoryQueryTests {
    private let day = HelmDay(year: 2026, month: 8, day: 3)

    @Test("parses recovery_query payload")
    func parsesQuery() {
        let text = """
        Checking trends.
        {"schemaVersion":"recovery_query.v1","queryType":"range","lookbackDays":7}
        """
        let payload = RecoveryQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .range)
        #expect(payload?.lookbackDays == 7)
    }

    @Test("range returns daily recovery lines with baselines")
    func rangeReturnsDays() async throws {
        let store = try PersistenceStore.inMemory()
        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: day,
                hrvSDNN: DurationMs(milliseconds: 48),
                restingHeartRate: 53,
                priorDayTRIMP: 30
            )
        )
        try store.readiness.upsertScore(
            helmDay: day,
            scoreJSON: """
            {"score":62,"band":"balanced","confidence":"medium","hrvBand":"typical","effectiveHRVMilliseconds":48.0,"restingHeartRate":53}
            """
        )
        try store.readiness.upsertBaseline(
            stateJSON: """
            {"hrvChronic":{"mean":55.0,"robustSigma":4.0},"restingHR":{"mean":51.0,"robustSigma":2.0},"seededNightCount":20}
            """
        )

        let now = Calendar.current.date(from: DateComponents(
            timeZone: .current,
            year: 2026,
            month: 8,
            day: 3,
            hour: 12
        ))!
        let service = RecoveryHistoryQueryService(store: store)
        let result = try await service.run(
            RecoveryQueryPayload(queryType: .range, lookbackDays: 7),
            now: now
        )
        #expect(result.contains("query=range"))
        #expect(result.contains("hrvChronicMs=55"))
        #expect(result.contains("readiness=62"))
        #expect(result.contains("hrv=48ms"))
        #expect(result.contains("hrvVsChronic=-7ms"))
    }

    @Test("sleepDetail formats night summary")
    func sleepDetailFormats() async throws {
        let store = try PersistenceStore.inMemory()
        let calendar = Calendar.current
        let wakeDay = calendar.date(from: DateComponents(
            timeZone: .current,
            year: 2026,
            month: 8,
            day: 3
        ))!
        let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
        let deepStart = windowStart.addingTimeInterval(3 * 3_600)
        let deepEnd = deepStart.addingTimeInterval(90 * 60)
        try store.sleep.upsert(
            SleepRecord(
                id: UUID(),
                start: deepStart,
                end: deepEnd,
                helmDay: day,
                stage: .asleepDeep
            )
        )

        let service = RecoveryHistoryQueryService(store: store, calendar: calendar)
        let result = try await service.run(
            RecoveryQueryPayload(queryType: .sleepDetail, helmDay: "2026-08-03"),
            now: wakeDay.addingTimeInterval(12 * 3_600)
        )
        #expect(result.contains("query=sleepDetail"))
        #expect(result.contains("day=2026-08-03"))
        #expect(result.contains("deepMin=90"))
    }
}
