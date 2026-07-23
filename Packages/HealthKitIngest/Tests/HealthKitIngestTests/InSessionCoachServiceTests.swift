import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("In-session coach")
struct InSessionCoachServiceTests {
    private let benchPressID = "bench_press"
    private let inclineDBPressID = "incline_db_press"
    private let cableFlyID = "cable_fly"

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.upsert(
            id: inclineDBPressID,
            canonicalName: "incline dumbbell press",
            displayName: "Incline DB Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.upsert(
            id: cableFlyID,
            canonicalName: "cable fly",
            displayName: "Cable Fly",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
    }

    private func startBenchSession(in store: PersistenceStore) async throws -> ActiveSessionSnapshot {
        let engine = ActiveSessionEngine(repository: store.activeSessions)
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 8,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                )
            ]
        )
        return try await engine.startFromPrescription(prescription)
    }

    @Test("swap adjustment applies and logs recommendation")
    func swapAppliesAndLogs() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Barbell rack is taken.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: benchPressID,
                    toExerciseID: inclineDBPressID
                )
            ]
        )

        let applied = try service.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: []
        )

        #expect(applied.banner.fromLabel == "Bench Press")
        #expect(applied.banner.toLabel == "Incline DB Press")
        #expect(applied.swappedExerciseIDs.contains(benchPressID))
        #expect(applied.swappedExerciseIDs.contains(inclineDBPressID))

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let exercise = try #require(refreshed?.session.exercises.first)
        #expect(exercise.exerciseID == inclineDBPressID)

        let recommendations = try store.coachRecommendations.fetchForSession(sessionID: snapshot.session.id)
        #expect(recommendations.count == 1)
        #expect(recommendations[0].actedOnAt != nil)
    }

    @Test("reorder adjustment applies cleanly")
    func reorderApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let engine = ActiveSessionEngine(repository: store.activeSessions)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            exercises: [
                PrescribedExercise(exerciseID: benchPressID, order: 0, targetSets: 3, targetRepMin: 8, targetRepMax: 8),
                PrescribedExercise(exerciseID: inclineDBPressID, order: 1, targetSets: 3, targetRepMin: 10, targetRepMax: 10)
            ]
        )
        let snapshot = try await engine.startFromPrescription(prescription)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Prioritise incline while fresh.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .reorder,
                    orderedExerciseIDs: [inclineDBPressID, benchPressID]
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let exercises = try #require(refreshed?.session.exercises.sorted { $0.displayOrder < $1.displayOrder })
        #expect(exercises[0].exerciseID == inclineDBPressID)
        #expect(exercises[1].exerciseID == benchPressID)
    }

    @Test("set adjustment applies cleanly")
    func adjustSetsApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Time is short; drop one set.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustSets,
                    exerciseID: benchPressID,
                    setDelta: -1
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let exercise = try #require(refreshed?.session.exercises.first)
        #expect(exercise.sets.count == 2)
    }

    @Test("undo restores previous exercise layout")
    func undoRestoresLayout() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let engine = ActiveSessionEngine(repository: store.activeSessions)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Swap test.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: benchPressID,
                    toExerciseID: inclineDBPressID
                )
            ]
        )

        let applied = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])
        try await engine.restoreExerciseLayout(applied.previousExercises)

        let restored = try store.activeSessions.fetchActiveSnapshot(at: Date())
        #expect(restored?.session.exercises.first?.exerciseID == benchPressID)
        #expect(restored?.session.exercises.first?.sets.count == 3)
    }

    @Test("second also-taken swap returns a different movement")
    func excludeListReturnsDifferentSwap() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        var excluded: Set<String> = []
        let firstPayload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Rack taken.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: benchPressID,
                    toExerciseID: inclineDBPressID
                )
            ]
        )
        let first = try service.applyAdjustment(
            payload: firstPayload,
            snapshot: snapshot,
            excludedExerciseIDs: excluded
        )
        excluded.formUnion(first.swappedExerciseIDs)

        let refreshed = try #require(try store.activeSessions.fetchActiveSnapshot(at: Date()))
        #expect(refreshed.session.exercises.first?.exerciseID == inclineDBPressID)

        let secondPayload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
            rationale: "Also taken.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: inclineDBPressID
                )
            ]
        )
        _ = try service.applyAdjustment(
            payload: secondPayload,
            snapshot: refreshed,
            excludedExerciseIDs: excluded
        )

        let final = try store.activeSessions.fetchActiveSnapshot(at: Date())
        #expect(final?.session.exercises.first?.exerciseID == cableFlyID)
    }
}
