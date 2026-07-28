import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Coach archetype support")
struct CoachArchetypeSupportTests {
    private func loadFixture() throws -> CoachArchetypeCatalog {
        let url = try #require(
            Bundle.module.url(
                forResource: "coach_archetype_catalog_fixture",
                withExtension: "json"
            )
        )
        return try CoachArchetypeLibrary.load(from: url)
    }

    @Test("fixture configures alias lookup for Jul 27 phrases")
    func jul27FixturePhrases() throws {
        let catalog = try loadFixture()
        CoachArchetypeSupport.configure(with: catalog)

        #expect(CoachArchetypeSupport.archetypeID(for: "incline db") == "incline_press")
        #expect(CoachArchetypeSupport.archetypeID(for: "flat bench") == "bench_press")
        #expect(CoachArchetypeSupport.archetypeID(for: "pec deck") == "chest_fly")
        #expect(CoachArchetypeSupport.archetypeID(for: "Seated Dumbbell Shoulder Press") == "shoulder_press")
    }
}

@Suite("Exercise resolver")
struct ExerciseResolverTests {
    private let benchPressID = "seed-bench-press"
    private let inclineID = "seed-incline-db-press"

    private func loadFixture() throws -> CoachArchetypeCatalog {
        let url = try #require(
            Bundle.module.url(
                forResource: "coach_archetype_catalog_fixture",
                withExtension: "json"
            )
        )
        return try CoachArchetypeLibrary.load(from: url)
    }

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.upsert(
            id: inclineID,
            canonicalName: "incline dumbbell press",
            displayName: "Incline DB Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
    }

    @Test("archetype ID resolves to preferred catalog exercise")
    func archetypeIDResolves() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        CoachArchetypeSupport.configure(with: try loadFixture())

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            mustBeInSession: false
        )
        let result = ExerciseResolver.resolve("incline_press", context: context, persistence: store)

        #expect(result.exerciseID == inclineID)
        #expect(result.archetypeID == "incline_press")
    }

    @Test("session archetype resolves to in-session exercise")
    func sessionArchetypeResolves() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        CoachArchetypeSupport.configure(with: try loadFixture())

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            mustBeInSession: true
        )
        let result = ExerciseResolver.resolve("bench_press", context: context, persistence: store)

        #expect(result.exerciseID == benchPressID)
    }
}
