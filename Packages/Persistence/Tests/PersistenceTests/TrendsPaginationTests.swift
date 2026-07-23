import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Trends pagination queries")
struct TrendsPaginationTests {
    private func makeStore() throws -> PersistenceStore {
        try PersistenceStore.inMemory()
    }

    @Test("readiness scores paginate newest first")
    func readinessPagination() throws {
        let store = try makeStore()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        for offset in 0 ..< 5 {
            let day = HelmDay(year: 2026, month: 7, day: 10 + offset)
            let score = ReadinessFixtureScore(score: 50 + offset)
            let data = try encoder.encode(score)
            let json = String(decoding: data, as: UTF8.self)
            try store.readiness.upsertScore(helmDay: day, scoreJSON: json)
        }

        let firstPage = try store.readiness.fetchScores(
            endingAt: HelmDay(year: 2026, month: 7, day: 20),
            limit: 2,
            offset: 0
        )
        #expect(firstPage.count == 2)
        #expect(firstPage[0].0 == HelmDay(year: 2026, month: 7, day: 14))
        #expect(firstPage[1].0 == HelmDay(year: 2026, month: 7, day: 13))

        let secondPage = try store.readiness.fetchScores(
            endingAt: HelmDay(year: 2026, month: 7, day: 20),
            limit: 2,
            offset: 2
        )
        #expect(secondPage.count == 2)
        #expect(secondPage[0].0 == HelmDay(year: 2026, month: 7, day: 12))
    }

    @Test("nutrition days paginate newest first")
    func nutritionPagination() throws {
        let store = try makeStore()

        for offset in 0 ..< 4 {
            let day = HelmDay(year: 2026, month: 7, day: 1 + offset)
            try store.nutrition.upsertDay(
                NutritionDay(
                    helmDay: day,
                    totalEnergy: Energy(kilocalories: 2_000 + Double(offset * 100))
                )
            )
        }

        let page = try store.nutrition.fetchDays(
            endingAt: HelmDay(year: 2026, month: 7, day: 10),
            limit: 2,
            offset: 0
        )
        #expect(page.count == 2)
        #expect(page[0].helmDay == HelmDay(year: 2026, month: 7, day: 4))
        #expect(page[1].helmDay == HelmDay(year: 2026, month: 7, day: 3))
    }

    @Test("daily body weights paginate newest first")
    func bodyWeightPagination() throws {
        let store = try makeStore()
        let measuredAt = Date(timeIntervalSince1970: 1_700_000_000)

        for offset in 0 ..< 3 {
            let day = HelmDay(year: 2026, month: 7, day: 5 + offset)
            try store.bodyComposition.upsert(
                BodyComposition(
                    helmDay: day,
                    mass: Mass(kilograms: 80 + Double(offset)),
                    measuredAt: measuredAt.addingTimeInterval(Double(offset) * 86_400)
                )
            )
        }

        let page = try store.bodyComposition.fetchDailyWeights(
            endingAt: HelmDay(year: 2026, month: 7, day: 20),
            limit: 2,
            offset: 0
        )
        #expect(page.count == 2)
        #expect(page[0].0 == HelmDay(year: 2026, month: 7, day: 7))
        #expect(page[0].1 == 82)
    }
}

private struct ReadinessFixtureScore: Codable {
    let score: Int
    let band: String
    let confidence: String
    let confidenceValue: Double
    let hrvBand: String
    let validNights: Int
    let stabilityScore: Double
    let contributors: ReadinessFixtureContributors
    let effectiveHRVMilliseconds: Double?
    let restingHeartRate: Int?

    init(score: Int) {
        self.score = score
        band = "balanced"
        confidence = "medium"
        confidenceValue = 0.7
        hrvBand = "typical"
        validNights = 7
        stabilityScore = 0.8
        contributors = ReadinessFixtureContributors()
        effectiveHRVMilliseconds = 55
        restingHeartRate = 52
    }
}

private struct ReadinessFixtureContributors: Codable {
    let zHRV: Double? = 0
    let zRestingHR: Double? = 0
    let zSleep: Double? = 0
    let zRespiratory: Double? = nil
    let zTemperature: Double? = nil
    let zStrain: Double? = 0
    let zComposite: Double? = 0
    let rawScore: Double? = 60
    let dampedScore: Double? = 60
}
