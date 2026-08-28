import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Coach archetype support", .serialized)
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

@Suite("Exercise resolver", .serialized)
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

    @Test("recents bias prefers recently used exercise for catalog phrase")
    func recentsBias() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-face-pull-cable",
            canonicalName: "face pull (cable)",
            displayName: "Face Pull",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "shoulders"
        )
        try store.exercises.upsert(
            id: "seed-face-pull-band",
            canonicalName: "face pull (band)",
            displayName: "Band Face Pull",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "shoulders"
        )
        try store.exercises.addAlias(
            id: "alias-face-pull",
            exerciseID: "seed-face-pull-cable",
            alias: "Face Pull"
        )

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: [],
            recentExerciseIDs: ["seed-face-pull-band"],
            mustBeInSession: false
        )
        let result = ExerciseResolver.resolve("face pull", context: context, persistence: store)

        #expect(result.exerciseID == "seed-face-pull-band")
    }

    @Test("FreeExerciseDB archetype member remaps to seed- catalog ID")
    func archetypeMemberSeedRemap() throws {        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-Hammer_Curls",
            canonicalName: "hammer curls",
            displayName: "Hammer Curls",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )
        try store.exercises.upsert(
            id: "seed-Cable_Hammer_Curls_-_Rope_Attachment",
            canonicalName: "cable hammer curls - rope attachment",
            displayName: "Cable Hammer Curls - Rope Attachment",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps"
        )

        let catalog = CoachArchetypeCatalog(
            schemaVersion: "coach_archetype_catalog.v1",
            generatedAt: "2026-07-31T00:00:00Z",
            archetypes: [
                CoachArchetype(
                    id: "hammer_curl",
                    displayName: "Hammer Curl",
                    priority: "accessory",
                    coachAliases: ["hammer curl", "rope hammer curl", "cable hammer curl"]
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
                        "Alternate_Hammer_Curl",
                        "Cable_Hammer_Curls_-_Rope_Attachment",
                        "Hammer_Curls"
                    ],
                    preferredDefaultExerciseId: "Hammer_Curls"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let defaultResult = ExerciseResolver.resolve(
            "hammer_curl",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )
        #expect(defaultResult.exerciseID == "seed-Hammer_Curls")

        let ropeResult = ExerciseResolver.resolve(
            "hammer_curl",
            context: ExerciseResolver.Context(
                sessionExerciseIDs: [],
                mustBeInSession: false,
                phraseHint: "add rope hammer curl"
            ),
            persistence: store
        )
        #expect(ropeResult.exerciseID == "seed-Cable_Hammer_Curls_-_Rope_Attachment")

        let phraseResult = ExerciseResolver.resolve(
            "rope hammer curl",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )
        #expect(phraseResult.exerciseID == "seed-Cable_Hammer_Curls_-_Rope_Attachment")
    }

    @Test("equipment mismatch returns candidates instead of silent collapse")
    func equipmentMismatchSurfacesCandidates() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-hip-thrust",
            canonicalName: "hip thrust (barbell)",
            displayName: "Hip Thrust (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "glutes"
        )

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: [],
            familiarExerciseIDs: ["seed-hip-thrust"],
            recentExerciseIDs: ["seed-hip-thrust"],
            mustBeInSession: false
        )
        let result = ExerciseResolver.resolve("hip thrust machine", context: context, persistence: store)

        #expect(result.exerciseID == nil)
        #expect(!result.catalogCandidates.isEmpty)
    }

    @Test("equipment wording picks matching variant when one exists")
    func equipmentWordingPicksVariant() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-hip-thrust",
            canonicalName: "hip thrust (barbell)",
            displayName: "Hip Thrust (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "glutes"
        )
        try store.exercises.upsert(
            id: "seed-cam-hip-thrust-machine",
            canonicalName: "hip thrust machine",
            displayName: "Hip Thrust (Machine)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "glutes"
        )
        try store.exercises.addAlias(id: "alias-htm", exerciseID: "seed-cam-hip-thrust-machine", alias: "hip thrust machine")

        let catalog = CoachArchetypeCatalog(
            schemaVersion: "coach_archetype_catalog.v1",
            generatedAt: nil,
            archetypes: [
                CoachArchetype(
                    id: "hip_thrust",
                    displayName: "Hip Thrust",
                    priority: "core",
                    coachAliases: ["hip thrust", "machine hip thrust"]
                )
            ],
            mapping: [
                "seed-hip-thrust": "hip_thrust",
                "seed-cam-hip-thrust-machine": "hip_thrust"
            ],
            variants: [
                "hip_thrust": CoachArchetypeVariants(
                    members: ["seed-cam-hip-thrust-machine", "seed-hip-thrust"],
                    preferredDefaultExerciseId: "seed-hip-thrust"
                )
            ]
        )
        CoachArchetypeSupport.configure(with: catalog)

        let result = ExerciseResolver.resolve(
            "machine hip thrust",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )

        #expect(result.exerciseID == "seed-cam-hip-thrust-machine")
    }

    @Test("plain phrase resolves via exact alias before fuzzy variants")
    func plainPushUpResolvesExactly() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-cam-push-up",
            canonicalName: "push up",
            displayName: "Push Up",
            exerciseMode: .bodyweightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.upsert(
            id: "seed-Suspended_Push-Up",
            canonicalName: "suspended push-up",
            displayName: "Suspended Push-Up",
            exerciseMode: .bodyweightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.addAlias(id: "alias-pushup", exerciseID: "seed-cam-push-up", alias: "push up")

        let result = ExerciseResolver.resolve(
            "push up",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )

        #expect(result.exerciseID == "seed-cam-push-up")
    }

    private func seedHammerVariants(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: "seed-cam-hammer-curl-cable",
            canonicalName: "hammer curl cable",
            displayName: "Hammer Curl (Cable)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps",
            isPickerDefault: true
        )
        try store.exercises.upsert(
            id: "seed-cam-hammer-curl-dumbbell",
            canonicalName: "hammer curl dumbbell",
            displayName: "Hammer Curl (Dumbbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps",
            isPickerDefault: true
        )
        try store.exercises.addAlias(
            id: "alias-hammer-cable",
            exerciseID: "seed-cam-hammer-curl-cable",
            alias: "Hammer Curl (Cable)"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-rope",
            exerciseID: "seed-cam-hammer-curl-cable",
            alias: "rope hammer curl"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-cable-phrase",
            exerciseID: "seed-cam-hammer-curl-cable",
            alias: "hammer curls cable"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-db",
            exerciseID: "seed-cam-hammer-curl-dumbbell",
            alias: "Hammer Curl (Dumbbell)"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-db-phrase",
            exerciseID: "seed-cam-hammer-curl-dumbbell",
            alias: "dumbbell hammer curls"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-db-short",
            exerciseID: "seed-cam-hammer-curl-dumbbell",
            alias: "db hammer curl"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-plain-cable",
            exerciseID: "seed-cam-hammer-curl-cable",
            alias: "hammer curl"
        )
        try store.exercises.addAlias(
            id: "alias-hammer-plain-db",
            exerciseID: "seed-cam-hammer-curl-dumbbell",
            alias: "hammer curl"
        )
    }

    @Test("rope hammer curl binds to cable not dumbbell")
    func ropeHammerBindsToCable() throws {
        let store = try PersistenceStore.inMemory()
        try seedHammerVariants(in: store)
        let context = ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false)

        #expect(
            ExerciseResolver.resolve("rope hammer curl", context: context, persistence: store).exerciseID
                == "seed-cam-hammer-curl-cable"
        )
        #expect(
            ExerciseResolver.resolve("hammer curls cable", context: context, persistence: store).exerciseID
                == "seed-cam-hammer-curl-cable"
        )
        #expect(
            ExerciseResolver.resolve("db hammer curl", context: context, persistence: store).exerciseID
                == "seed-cam-hammer-curl-dumbbell"
        )
        #expect(
            ExerciseResolver.resolve("dumbbell hammer curls", context: context, persistence: store).exerciseID
                == "seed-cam-hammer-curl-dumbbell"
        )
    }

    @Test("bare hammer curl stays unresolved when both variants exist")
    func bareHammerCurlIsAmbiguous() throws {
        let store = try PersistenceStore.inMemory()
        try seedHammerVariants(in: store)
        let result = ExerciseResolver.resolve(
            "hammer curl",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )
        #expect(result.exerciseID == nil)
    }

    @Test("bare hammer curl resolves when only the dumbbell variant exists")
    func bareHammerResolvesIfUnambiguous() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: "seed-cam-hammer-curl-dumbbell",
            canonicalName: "hammer curl dumbbell",
            displayName: "Hammer Curl (Dumbbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "biceps",
            isPickerDefault: true
        )
        try store.exercises.addAlias(
            id: "alias-only-hammer",
            exerciseID: "seed-cam-hammer-curl-dumbbell",
            alias: "hammer curl"
        )
        let result = ExerciseResolver.resolve(
            "hammer curl",
            context: ExerciseResolver.Context(sessionExerciseIDs: [], mustBeInSession: false),
            persistence: store
        )
        #expect(result.exerciseID == "seed-cam-hammer-curl-dumbbell")
    }
}
