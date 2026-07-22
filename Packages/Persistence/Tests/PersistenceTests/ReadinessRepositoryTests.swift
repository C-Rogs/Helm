import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Readiness repository")
struct ReadinessRepositoryTests {
    private let day = HelmDay(year: 2026, month: 7, day: 22)

    @Test("baseline and score round trip")
    func baselineAndScoreRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let scoreJSON = """
        {"score":72,"band":"primed","confidence":"high","confidenceValue":0.8,"hrvBand":"typical","validNights":18,"stabilityScore":0.9,"contributors":{"zHRV":0.5,"zRestingHR":-0.1,"zSleep":0.3,"zRespiratory":null,"zTemperature":null,"zStrain":null,"zComposite":0.2,"rawScore":70.0,"dampedScore":72.0},"effectiveHRVMilliseconds":52.0,"restingHeartRate":51}
        """
        let baselineJSON = """
        {"seededNightCount":30}
        """

        try store.readiness.upsertScore(helmDay: day, scoreJSON: scoreJSON)
        try store.readiness.upsertBaseline(stateJSON: baselineJSON)

        #expect(try store.readiness.fetchScoreJSON(helmDay: day) == scoreJSON)
        #expect(try store.readiness.fetchBaselineJSON() == baselineJSON)
    }

    @Test("score range query")
    func scoreRange() throws {
        let store = try PersistenceStore.inMemory()
        let previous = HelmDay(year: 2026, month: 7, day: 21)
        try store.readiness.upsertScore(helmDay: previous, scoreJSON: "{\"score\":60}")
        try store.readiness.upsertScore(helmDay: day, scoreJSON: "{\"score\":72}")

        let range = try store.readiness.fetchScoreRange(from: previous, through: day)

        #expect(range.map(\.0) == [previous, day])
        #expect(range.map(\.1) == ["{\"score\":60}", "{\"score\":72}"])
    }
}
