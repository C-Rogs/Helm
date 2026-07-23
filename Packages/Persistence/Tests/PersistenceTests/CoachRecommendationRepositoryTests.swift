import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Coach recommendation repository")
struct CoachRecommendationRepositoryTests {
    @Test("insert and fetch round trip")
    func insertAndFetch() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ActiveSessionEngine(repository: store.activeSessions)
        try store.exercises.upsert(
            id: "bench_press",
            canonicalName: "bench press",
            displayName: "Bench Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )

        let snapshot = try await engine.start()
        let recommendation = try store.coachRecommendations.insert(
            CoachRecommendationInsert(
                scope: .session,
                workoutSessionID: snapshot.session.id,
                recommendationType: .sessionAdjustment,
                payloadJSON: #"{"rationale":"test"}"#
            )
        )

        try store.coachRecommendations.markActedOn(id: recommendation.id)

        let fetched = try store.coachRecommendations.fetch(id: recommendation.id)
        #expect(fetched?.actedOnAt != nil)

        let sessionRows = try store.coachRecommendations.fetchForSession(sessionID: snapshot.session.id)
        #expect(sessionRows.count == 1)
    }
}
