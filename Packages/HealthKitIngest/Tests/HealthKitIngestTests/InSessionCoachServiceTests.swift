import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("In-session coach", .serialized)
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

    @Test("reorder adjustment preserves logged set weights on each exercise")
    func reorderPreservesLoggedWeights() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
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
                ),
                PrescribedExercise(
                    exerciseID: inclineDBPressID,
                    order: 1,
                    targetSets: 3,
                    targetRepMin: 10,
                    targetRepMax: 10,
                    targetMass: Mass(kilograms: 30),
                    targetRPE: 8
                )
            ]
        )
        var snapshot = try await engine.startFromPrescription(prescription)

        let benchExercise = try #require(snapshot.session.exercises.first { $0.exerciseID == benchPressID })
        let inclineExercise = try #require(snapshot.session.exercises.first { $0.exerciseID == inclineDBPressID })
        let benchSet = try #require(benchExercise.sets.first)
        let inclineSet = try #require(inclineExercise.sets.first)

        snapshot = try await engine.logSet(
            setID: benchSet.id,
            update: SetLogUpdate(mass: Mass(kilograms: 82.5), reps: 8)
        )
        snapshot = try await engine.logSet(
            setID: inclineSet.id,
            update: SetLogUpdate(mass: Mass(kilograms: 32.5), reps: 10)
        )

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

        let reorderedInclineSet = try #require(exercises[0].sets.first)
        let reorderedBenchSet = try #require(exercises[1].sets.first)
        #expect(reorderedInclineSet.id == inclineSet.id)
        #expect(reorderedInclineSet.mass?.kilograms == 32.5)
        #expect(reorderedBenchSet.id == benchSet.id)
        #expect(reorderedBenchSet.mass?.kilograms == 82.5)
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

    @Test("advisory payload does not apply session changes")
    func advisoryPayloadDoesNotApply() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Stay at 80 kg today.",
            operations: []
        )

        do {
            _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])
            Issue.record("Expected noApplicableChange for advisory payload")
        } catch InSessionCoachError.noApplicableChange {
            #expect(true)
        }

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        #expect(refreshed?.session.exercises.first?.exerciseID == benchPressID)
        #expect(refreshed?.session.exercises.first?.sets.count == 3)
    }

    @Test("pre-start advisory proposal logs without workout session FK")
    func preStartAdvisoryLogsWithoutWorkoutSessionFK() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 30),
            exercises: [
                PrescribedExercise(
                    exerciseID: inclineDBPressID,
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 10,
                    targetRepMax: 10
                )
            ]
        )
        let snapshot = PrescriptionCoachSnapshotBuilder.snapshot(from: prescription)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Today is incline-focused horizontal press; flat bench rotates on the next push day.",
            operations: []
        )

        let proposal = try service.buildProposal(
            payload: payload,
            userMessage: "Why are we not including bench press or dumbbell press?",
            snapshot: snapshot,
            excludedExerciseIDs: [],
            modelVersion: payload.schemaVersion
        )

        #expect(proposal.status == .advisory)
        let stored = try store.coachRecommendations.fetch(id: proposal.recommendationID)
        #expect(stored?.workoutSessionID == nil)
    }

    @Test("load adjustment applies and logs on confirm")
    func adjustLoadAppliesAndLogs() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Bump bench to 82.5 kg.",
            rationale: "Progression bump.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    massDeltaKg: 2.5
                )
            ]
        )

        let stored = try store.coachRecommendations.insert(
            CoachRecommendationInsert(
                scope: .session,
                workoutSessionID: snapshot.session.id,
                recommendationType: .sessionAdjustment,
                payloadJSON: "{}",
                modelVersion: payload.schemaVersion
            )
        )

        let proposal = CoachSessionProposal(
            reply: payload.reply,
            payload: payload,
            recommendationID: stored.id,
            previewBanner: SessionAdjustmentBannerModel(
                fromLabel: "Bench Press",
                toLabel: "82.5 kg",
                reason: payload.bannerReason,
                recommendationID: stored.id
            ),
            status: .confirmable
        )

        let result = try await service.applyProposal(
            proposal,
            snapshot: snapshot,
            excludedExerciseIDs: []
        )

        #expect(result.sessionAdjustment?.banner.toLabel == "82.5 kg")
        #expect(result.sideEffects.contains(.refreshPrescription))

        let recommendations = try store.coachRecommendations.fetchForSession(sessionID: snapshot.session.id)
        #expect(recommendations.count == 1)
        #expect(recommendations[0].actedOnAt != nil)
    }

    @Test("user-directed large load increase applies with user message")
    func userDirectedLargeLoadApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Bench to 100 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    targetMassKg: 100
                )
            ]
        )

        let applied = try service.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: [],
            userMessage: "Set bench to 100 kg"
        )

        #expect(applied.banner.toLabel == "100 kg")
    }

    @Test("coach add exercise appends to session")
    func addExerciseApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        try store.exercises.upsert(
            id: cableFlyID,
            canonicalName: "cable fly",
            displayName: "Cable Fly",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Adding cable fly finisher.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .addExercise,
                    toExerciseID: cableFlyID,
                    targetSets: 2
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let exercises = try #require(refreshed?.session.exercises.sorted { $0.displayOrder < $1.displayOrder })
        #expect(exercises.count == 2)
        #expect(exercises[1].exerciseID == cableFlyID)
        #expect(exercises[1].sets.count == 2)
    }

    @Test("coach add exercise proposal resolves archetype phrase against catalogue")
    func addExerciseProposalResolvesCataloguePhrase() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let ropeID = "seed-Cable_Hammer_Curls_-_Rope_Attachment"
        try store.exercises.upsert(
            id: "seed-Hammer_Curls",
            canonicalName: "hammer curls",
            displayName: "Hammer Curls",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )
        try store.exercises.upsert(
            id: ropeID,
            canonicalName: "cable hammer curls - rope attachment",
            displayName: "Cable Hammer Curls - Rope Attachment",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )

        let catalog = CoachArchetypeCatalog(
            schemaVersion: "coach_archetype_catalog.v1",
            archetypes: [
                CoachArchetype(
                    id: "hammer_curl",
                    displayName: "Hammer Curl",
                    coachAliases: ["hammer curl", "rope hammer curl"]
                )
            ],
            mapping: [
                "Hammer_Curls": "hammer_curl",
                "Cable_Hammer_Curls_-_Rope_Attachment": "hammer_curl",
                ropeID: "hammer_curl",
                "seed-Hammer_Curls": "hammer_curl"
            ],
            variants: [
                "hammer_curl": CoachArchetypeVariants(
                    members: ["Cable_Hammer_Curls_-_Rope_Attachment", "Hammer_Curls"],
                    preferredDefaultExerciseId: "Hammer_Curls"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Adding rope hammer curl.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .addExercise,
                    toExerciseID: "hammer_curl",
                    targetSets: 3
                )
            ]
        )

        let proposal = try service.buildProposal(
            payload: payload,
            userMessage: "add rope hammer curl",
            snapshot: snapshot,
            excludedExerciseIDs: [],
            modelVersion: payload.schemaVersion
        )

        #expect(proposal.requiresConfirmation)
        #expect(proposal.payload.operations.first?.toExerciseID == ropeID)
        #expect(proposal.previewBanner?.toLabel.contains("Cable") == true
            || proposal.previewBanner?.toLabel.lowercased().contains("rope") == true
            || proposal.previewBanner?.toLabel.lowercased().contains("hammer") == true)
    }

    @Test("large coach-suggested load increase applies")
    func largeLoadIncreaseApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Jumping bench to 100 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    targetMassKg: 100
                )
            ]
        )

        let applied = try service.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: []
        )

        #expect(applied.banner.toLabel == "100 kg")
        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let working = try #require(refreshed?.session.exercises.first).sets.filter {
            $0.setType.countsAsPrescribedWorkingSet
        }
        #expect(working.allSatisfy { $0.mass?.kilograms == 100 })
    }

    @Test("load adjustment writes remaining planned set weights")
    func adjustLoadWritesPlannedSetWeights() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Bench to 100 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    targetMassKg: 100
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let exercise = try #require(refreshed?.session.exercises.first)
        let working = exercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }
        #expect(working.count == 3)
        #expect(working.allSatisfy { $0.mass?.kilograms == 100 })
        #expect(working.allSatisfy { $0.status == .planned })
    }

    @Test("load adjustment fills empty planned weights")
    func adjustLoadFillsEmptyPlannedWeights() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let engine = ActiveSessionEngine(repository: store.activeSessions)
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 8
                )
            ]
        )
        let snapshot = try await engine.startFromPrescription(prescription)
        #expect(snapshot.session.exercises.first?.sets.allSatisfy { $0.mass == nil } == true)

        let service = InSessionCoachService(persistence: store)
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Let's start bench at 80 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    targetMassKg: 80
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let working = try #require(refreshed?.session.exercises.first).sets.filter {
            $0.setType.countsAsPrescribedWorkingSet
        }
        #expect(working.allSatisfy { $0.mass?.kilograms == 80 })
    }

    @Test("load adjustment does not overwrite completed sets or warm-ups")
    func adjustLoadPreservesCompletedAndWarmupLoads() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let engine = ActiveSessionEngine(repository: store.activeSessions)
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 2,
                    targetRepMin: 8,
                    targetRepMax: 8,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                )
            ]
        )
        var snapshot = try await engine.startFromPrescription(prescription)
        let exercise = try #require(snapshot.session.exercises.first)
        let firstWorking = try #require(
            exercise.sets.first { $0.setType.countsAsPrescribedWorkingSet }
        )
        snapshot = try await engine.logSet(
            setID: firstWorking.id,
            update: SetLogUpdate(mass: Mass(kilograms: 82.5), reps: 8)
        )
        snapshot = try await engine.completeSet(
            sessionExerciseID: exercise.id,
            setID: firstWorking.id
        )

        let service = InSessionCoachService(persistence: store)
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Take remaining bench sets to 100 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: benchPressID,
                    targetMassKg: 100
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let sets = try #require(refreshed?.session.exercises.first?.sets)
        let warmups = sets.filter { $0.setType.isWarmup }
        let completed = sets.filter { $0.status == .completed }
        let plannedWorking = sets.filter {
            $0.setType.countsAsPrescribedWorkingSet && $0.status == .planned
        }
        #expect(warmups.count == 2)
        #expect(warmups.allSatisfy { $0.mass?.kilograms == 80 })
        #expect(completed.count == 1)
        #expect(completed.first?.mass?.kilograms == 82.5)
        #expect(plannedWorking.count == 2)
        #expect(plannedWorking.allSatisfy { $0.mass?.kilograms == 100 })
    }

    @Test("add exercise with a named weight writes it onto new sets")
    func addExerciseWritesNamedWeight() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        try store.exercises.upsert(
            id: cableFlyID,
            canonicalName: "cable fly",
            displayName: "Cable Fly",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Adding cable fly at 15 kg.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .addExercise,
                    toExerciseID: cableFlyID,
                    targetMassKg: 15,
                    targetSets: 2
                )
            ]
        )

        _ = try service.applyAdjustment(payload: payload, snapshot: snapshot, excludedExerciseIDs: [])

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        let fly = try #require(
            refreshed?.session.exercises.first { $0.exerciseID == cableFlyID }
        )
        #expect(fly.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count == 2)
        #expect(fly.sets.allSatisfy { $0.mass?.kilograms == 15 })
    }

    @Test("set adds past the engine cap apply")
    func setAddPastEngineCapApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Adding five sets on bench.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustSets,
                    exerciseID: benchPressID,
                    setDelta: 5
                )
            ]
        )

        let applied = try service.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: []
        )

        #expect(applied.banner.toLabel == "+5 sets")
    }

    @Test("warmup set add applies without changing working set count")
    func warmupSetAddApplies() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let service = InSessionCoachService(persistence: store)

        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Adding two warm-up sets on bench.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustWarmupSets,
                    exerciseID: benchPressID,
                    setDelta: 2
                )
            ]
        )

        let applied = try service.applyAdjustment(
            payload: payload,
            snapshot: snapshot,
            excludedExerciseIDs: []
        )
        #expect(applied.banner.toLabel == "+2 warm-up")

        let refreshed = try #require(try store.activeSessions.fetchActiveSnapshot(at: Date()))
        let bench = try #require(refreshed.session.exercises.first { $0.exerciseID == benchPressID })
        #expect(bench.sets.filter { $0.setType.isWarmup }.count == 2)
        #expect(bench.sets.filter { !$0.setType.isWarmup }.count == 3)

        let bridged = ActiveSessionPrescriptionBridge.prescribedSession(from: refreshed)
        let bridgedBench = try #require(bridged.exercises.first { $0.exerciseID == benchPressID })
        #expect(bridgedBench.targetSets == 3)
        #expect(bridgedBench.warmupSets == 2)
    }
}
