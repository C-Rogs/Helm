import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Session exercise ID resolver")
struct SessionExerciseIDResolverTests {
    private let benchPressID = "seed-bench-press"
    private let inclineID = "seed-incline-db-press"

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

    @Test("fuzzy match maps alias to session exercise ID")
    func fuzzyMatchAlias() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Bump load.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: 2.5
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            persistence: store
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.exerciseID == benchPressID)
    }

    @Test("display name maps to session exercise ID")
    func displayNameMatch() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Bump load.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "Bench Press",
                    massDeltaKg: 2.5
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            persistence: store
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.exerciseID == benchPressID)
    }

    @Test("unknown exercise ID is unresolved")
    func unknownExerciseID() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Swap movement.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "totally-unknown-lift",
                    massDeltaKg: 2.5
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            persistence: store
        )

        #expect(result.unresolvedExerciseIDs.contains("totally-unknown-lift"))
    }

    @Test("archetype ID resolves swap target to catalog exercise")
    func archetypeSwapTarget() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "coach_archetype_catalog_fixture",
                withExtension: "json"
            )
        )
        CoachArchetypeSupport.configure(with: try CoachArchetypeLibrary.load(from: fixtureURL))

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Swap to incline.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: "bench_press",
                    toExerciseID: "incline_press"
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            persistence: store
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.fromExerciseID == benchPressID)
        #expect(result.payload.operations.first?.toExerciseID == inclineID)
    }
}

@Suite("In-session coach proposal status")
struct InSessionCoachProposalStatusTests {
    private let benchPressID = "bench_press"

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press",
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

    @Test("unresolved exercise ID yields failed proposal without confirmation")
    func unresolvedIDFailsProposal() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "I'll bump your bench load.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "unknown-lift",
                    massDeltaKg: 2.5
                )
            ]
        )

        let proposal = try service.buildProposal(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: [],
            modelVersion: payload.schemaVersion
        )

        #expect(proposal.requiresConfirmation == false)
        if case .failed(.unresolvedExerciseIDs) = proposal.status {
            #expect(true)
        } else {
            Issue.record("Expected failed unresolvedExerciseIDs status")
        }
        #expect(proposal.failureNotice?.contains("Available exercises") == true)
        #expect(proposal.failureNotice?.contains("Bench Press") == true)
    }

    @Test("resolved load proposal is confirmable")
    func resolvedLoadIsConfirmable() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Bump bench to 82.5 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    massDeltaKg: 2.5
                )
            ]
        )

        let proposal = try service.buildProposal(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: [],
            modelVersion: payload.schemaVersion
        )

        #expect(proposal.requiresConfirmation)
        if case .confirmable = proposal.status {
            #expect(proposal.previewBanner?.toLabel == "82.5 kg")
        } else {
            Issue.record("Expected confirmable status")
        }
    }
}
