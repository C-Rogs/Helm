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

    @Test("addExercise resolves FreeExerciseDB archetype via seed remap and phrase hint")
    func addExerciseArchetypeSeedRemap() throws {
        let store = try PersistenceStore.inMemory()
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
                "Cable_Hammer_Curls_-_Rope_Attachment": "hammer_curl"
            ],
            variants: [
                "hammer_curl": CoachArchetypeVariants(
                    members: ["Cable_Hammer_Curls_-_Rope_Attachment", "Hammer_Curls"],
                    preferredDefaultExerciseId: "Hammer_Curls"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Adding hammer curl.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .addExercise,
                    toExerciseID: "hammer_curl",
                    targetSets: 3
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [benchPressID],
            exerciseDisplayNames: [benchPressID: "Bench Press"],
            persistence: store,
            phraseHint: "add rope hammer curl"
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.toExerciseID == ropeID)
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

    @Test("lat_pulldown archetype resolves adjustWarmupSets to session catalog ID")
    func latPulldownWarmupUsesSessionID() throws {
        let store = try PersistenceStore.inMemory()
        let latID = "seed-Wide-Grip_Lat_Pulldown"
        try store.exercises.upsert(
            id: latID,
            canonicalName: "wide grip lat pulldown",
            displayName: "Wide-Grip Lat Pulldown",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "lats"
        )
        let catalog = CoachArchetypeCatalog(
            schemaVersion: "coach_archetype_catalog.v1",
            generatedAt: "2026-08-10T00:00:00Z",
            archetypes: [
                CoachArchetype(
                    id: "lat_pulldown",
                    displayName: "Lat Pulldown",
                    priority: "core",
                    coachAliases: ["lat pulldown", "wide grip lat pulldown"]
                )
            ],
            mapping: [
                "Wide-Grip_Lat_Pulldown": "lat_pulldown",
                "seed-Wide-Grip_Lat_Pulldown": "lat_pulldown",
                "seed-lat-pulldown": "lat_pulldown"
            ],
            variants: [
                "lat_pulldown": CoachArchetypeVariants(
                    members: ["Wide-Grip_Lat_Pulldown", "seed-lat-pulldown"],
                    preferredDefaultExerciseId: "seed-lat-pulldown"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Added warm-ups.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustWarmupSets,
                    exerciseID: "lat_pulldown",
                    setDelta: 2
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [latID],
            exerciseDisplayNames: [latID: "Wide-Grip Lat Pulldown"],
            persistence: store
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.exerciseID == latID)
    }

    @Test("same-archetype swap excludes from so rope becomes dumbbell")
    func hammerCurlRopeToDumbbellSwap() throws {
        let store = try PersistenceStore.inMemory()
        let ropeID = "seed-Cable_Hammer_Curls_-_Rope_Attachment"
        let dbID = "seed-Hammer_Curls"
        try store.exercises.upsert(
            id: ropeID,
            canonicalName: "cable hammer curls - rope attachment",
            displayName: "Cable Hammer Curls - Rope Attachment",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )
        try store.exercises.upsert(
            id: dbID,
            canonicalName: "hammer curls",
            displayName: "Hammer Curls",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )
        let catalog = CoachArchetypeCatalog(
            schemaVersion: "coach_archetype_catalog.v1",
            generatedAt: "2026-08-10T00:00:00Z",
            archetypes: [
                CoachArchetype(
                    id: "hammer_curl",
                    displayName: "Hammer Curl",
                    priority: "accessory",
                    coachAliases: ["hammer curl", "rope hammer curl", "dumbbell hammer curl"]
                )
            ],
            mapping: [
                "Hammer_Curls": "hammer_curl",
                "Cable_Hammer_Curls_-_Rope_Attachment": "hammer_curl",
                "seed-Hammer_Curls": "hammer_curl",
                "seed-Cable_Hammer_Curls_-_Rope_Attachment": "hammer_curl"
            ],
            variants: [
                "hammer_curl": CoachArchetypeVariants(
                    members: [
                        "Cable_Hammer_Curls_-_Rope_Attachment",
                        "Hammer_Curls"
                    ],
                    preferredDefaultExerciseId: "Hammer_Curls"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let payload = SessionAdjustmentPayload(
            schemaVersion: "session_adjustment.v2",
            reply: "Swapping to dumbbells.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: "hammer_curl",
                    toExerciseID: "hammer_curl"
                )
            ]
        )

        let result = try SessionExerciseIDResolver.normalize(
            payload: payload,
            sessionExerciseIDs: [ropeID],
            exerciseDisplayNames: [ropeID: "Cable Hammer Curls - Rope Attachment"],
            persistence: store,
            phraseHint: "Replace hammer curls rope attachment for hammer curls dumbbell"
        )

        #expect(result.unresolvedExerciseIDs.isEmpty)
        #expect(result.payload.operations.first?.fromExerciseID == ropeID)
        #expect(result.payload.operations.first?.toExerciseID == dbID)
        #expect(result.payload.operations.first?.fromExerciseID != result.payload.operations.first?.toExerciseID)
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
