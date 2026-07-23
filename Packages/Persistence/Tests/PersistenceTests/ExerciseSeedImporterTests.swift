import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Exercise seed import")
struct ExerciseSeedImporterTests {
    private func fixtureURL(_ name: String) throws -> URL {
        if let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "json") {
            return url
        }
        Issue.record("Missing fixture \(name).json")
        throw FixtureError.missing
    }

    @Test("placeholder manifest round-trips into GRDB")
    func placeholderRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let manifestURL = try fixtureURL("exercise_seed_v1")
        let manifestData = try Data(contentsOf: manifestURL)

        let manifest = try ExerciseSeedLoader.loadManifest(from: manifestData)
        #expect(manifest.placeholder)
        #expect(manifest.seedVersion == 1)
        #expect(manifest.exercises.count == 2)

        let result = try importer.importIfNeeded(manifestURL: manifestURL, manifestData: manifestData)
        #expect(result.importedCount == 2)
        #expect(result.appliedSeedVersion == 1)
        #expect(try store.exercises.exerciseCount() == 2)

        let bench = try store.exercises.fetchSummary(id: "seed-bench-press")
        #expect(bench?.displayName == "Bench Press (Barbell)")
        #expect(bench?.primaryMuscleGroup == "chest")

        let resolved = try store.exercises.resolveImportedTitle("Bench Press")
        #expect(resolved?.exerciseID == "seed-bench-press")
    }

    @Test("re-import at same version is idempotent")
    func reimportIdempotent() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let manifestURL = try fixtureURL("exercise_seed_v1")
        let manifestData = try Data(contentsOf: manifestURL)

        _ = try importer.importIfNeeded(manifestURL: manifestURL, manifestData: manifestData)
        let second = try importer.importIfNeeded(manifestURL: manifestURL, manifestData: manifestData)

        #expect(second.skippedBecauseUpToDate)
        #expect(second.importedCount == 0)
        #expect(try store.exercises.exerciseCount() == 2)
    }

    @Test("version bump updates rows without duplicates")
    func versionBumpUpdatesWithoutDuplicates() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let v1URL = try fixtureURL("exercise_seed_v1")
        let v1Data = try Data(contentsOf: v1URL)
        let v2URL = try fixtureURL("exercise_seed_v2")
        let v2Data = try Data(contentsOf: v2URL)

        _ = try importer.importIfNeeded(manifestURL: v1URL, manifestData: v1Data)
        let bumped = try importer.importIfNeeded(manifestURL: v2URL, manifestData: v2Data)

        #expect(bumped.appliedSeedVersion == 2)
        #expect(bumped.importedCount == 3)
        #expect(try store.exercises.exerciseCount() == 3)
        #expect(try importer.appliedSeedVersion() == 2)

        let deadlift = try store.exercises.fetchSummary(id: "seed-deadlift")
        #expect(deadlift?.displayName == "Deadlift (Barbell)")
    }

    @Test("free-exercise-db catalog maps loggy-style entries")
    func freeExerciseDBMapping() throws {
        let record = FreeExerciseDBRecord(
            id: "Barbell_Bench_Press",
            name: "Barbell Bench Press",
            force: "push",
            level: "beginner",
            mechanic: "compound",
            equipment: "barbell",
            primaryMuscles: ["chest"],
            secondaryMuscles: ["shoulders", "triceps"],
            instructions: ["Lie on bench", "Press up"],
            category: "strength",
            images: ["Barbell_Bench_Press/0.jpg"]
        )

        let entry = ExerciseSeedCatalogMapper.mapRecord(record)
        #expect(entry.id == "seed-Barbell_Bench_Press")
        #expect(entry.canonicalName == "barbell bench press")
        #expect(entry.displayName == "Bench Press (Barbell)")
        #expect(entry.exerciseMode == .weightReps)
        #expect(entry.primaryMuscleGroup == "chest")
        #expect(entry.aliases.contains("Bench Press (Barbell)"))
    }
}

private enum FixtureError: Error {
    case missing
}
