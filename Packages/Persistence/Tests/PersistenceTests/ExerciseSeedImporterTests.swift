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

    @Test("coaching cues import into GRDB on version bump")
    func coachingCuesImport() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let entry = ExerciseSeedEntry(
            id: "seed-bench-press",
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press (Barbell)",
            aliases: ["Bench Press"],
            exerciseMode: .weightReps,
            coachingCues: [
                "Brace hard and pull shoulder blades together.",
                "Press up and slightly back."
            ]
        )
        _ = try importer.importEntries([entry], seedVersion: 1)
        let cues = try store.exercises.fetchCoachingCues(id: "seed-bench-press")
        #expect(cues.count == 2)
        #expect(cues[0] == "Brace hard and pull shoulder blades together.")
    }

    @Test("version bump retains previously imported exercises")
    func versionBumpRetainsExercises() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let v1URL = try fixtureURL("exercise_seed_v1")
        let v1Data = try Data(contentsOf: v1URL)

        let replacementManifest = """
        {
          "seedVersion": 2,
          "placeholder": false,
          "exercises": [
            {
              "id": "seed-bench-press",
              "canonicalName": "bench press (barbell)",
              "displayName": "Bench Press (Barbell)",
              "aliases": ["Bench Press"],
              "exerciseMode": "weight_reps",
              "equipment": "barbell",
              "primaryMuscleGroup": "chest",
              "secondaryMuscleGroups": [],
              "isPickerDefault": true,
              "isHevyLibrary": true
            },
            {
              "id": "seed-deadlift",
              "canonicalName": "deadlift (barbell)",
              "displayName": "Deadlift (Barbell)",
              "aliases": ["Deadlift"],
              "exerciseMode": "weight_reps",
              "equipment": "barbell",
              "primaryMuscleGroup": "hamstrings",
              "secondaryMuscleGroups": [],
              "isPickerDefault": true,
              "isHevyLibrary": true
            }
          ]
        }
        """
        let replacementData = Data(replacementManifest.utf8)
        let replacementURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exercise_seed_retain_test.json")
        try replacementData.write(to: replacementURL)

        _ = try importer.importIfNeeded(manifestURL: v1URL, manifestData: v1Data)
        #expect(try store.exercises.exerciseCount() == 2)

        _ = try importer.importIfNeeded(manifestURL: replacementURL, manifestData: replacementData)
        #expect(try store.exercises.exerciseCount() == 3)
        #expect(try store.exercises.fetchSummary(id: "seed-bench-press") != nil)
        #expect(try store.exercises.fetchSummary(id: "seed-deadlift") != nil)
        #expect(try store.exercises.fetchSummary(id: "seed-squat") != nil)
    }

    @Test("hybrid manifest imports full catalog with explicit picker defaults")
    func hybridManifestImport() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let manifestURL = try fixtureURL("exercise_seed_hybrid")
        let manifestData = try Data(contentsOf: manifestURL)

        let resolved = try ExerciseSeedLoader.resolveEntries(
            manifest: try ExerciseSeedLoader.loadManifest(from: manifestData),
            manifestDirectory: manifestURL.deletingLastPathComponent()
        )
        #expect(resolved.entries.count == 7)
        #expect(resolved.pickerCuration == .explicit)
        #expect(resolved.explicitPickerIDs.count == 3)

        _ = try importer.importIfNeeded(manifestURL: manifestURL, manifestData: manifestData)
        #expect(try store.exercises.exerciseCount() == 5)

        let defaults = try store.exercises.listForPicker(search: nil)
        #expect(defaults.count == 3)
        #expect(defaults.contains { $0.id == "seed-horizontal-leg-press" })

        let stretchResults = try store.exercises.listForPicker(search: "90/90")
        #expect(stretchResults.contains { $0.displayName.contains("90/90") })
    }

    @Test("picker search resolves Hevy naming examples")
    func hevyNamingSearchExamples() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let manifestURL = try fixtureURL("exercise_seed_hybrid")
        let manifestData = try Data(contentsOf: manifestURL)
        _ = try importer.importIfNeeded(manifestURL: manifestURL, manifestData: manifestData)

        let legPress = try store.exercises.listForPicker(search: "Horizontal Leg Press")
        #expect(legPress.contains { $0.displayName == "Leg Press Horizontal (Machine)" })

        let facePull = try store.exercises.resolveImportedTitle("Face Pull")
        #expect(facePull?.exerciseID == "seed-face-pull-overlay")

        let legCurl = try store.exercises.listForPicker(search: "Lying Leg Curl")
        #expect(legCurl.contains { $0.displayName == "Lying Leg Curl (Machine)" })
    }

    @Test("Hevy aliases resolve for curated gym staples")
    func hevyAliasResolution() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)
        let manifest = """
        {
          "seedVersion": 1,
          "placeholder": false,
          "exercises": [
            {
              "id": "seed-horizontal-leg-press",
              "canonicalName": "horizontal leg press",
              "displayName": "Leg Press Horizontal (Machine)",
              "aliases": ["Leg Press Horizontal (Machine)", "Horizontal Leg Press"],
              "exerciseMode": "weight_reps",
              "equipment": "machine",
              "primaryMuscleGroup": "quadriceps",
              "secondaryMuscleGroups": [],
              "isPickerDefault": true,
              "isHevyLibrary": true
            }
          ]
        }
        """
        let data = Data(manifest.utf8)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("exercise_seed_hevy_alias.json")
        try data.write(to: url)

        _ = try importer.importIfNeeded(manifestURL: url, manifestData: data)
        let resolved = try store.exercises.resolveImportedTitle("Leg Press Horizontal (Machine)")
        #expect(resolved?.exerciseID == "seed-horizontal-leg-press")
    }

    @Test("hiddenIDs soft-deletes catalogue rows but keeps custom rows")
    func hiddenIDSoftDeletes() throws {
        let store = try PersistenceStore.inMemory()
        let importer = ExerciseSeedImporter(pool: store.poolForTesting)

        let manifest = """
        {
          "seedVersion": 7,
          "placeholder": false,
          "hiddenIDs": ["seed-bench-press"],
          "exercises": [
            {
              "id": "seed-bench-press",
              "canonicalName": "bench press (barbell)",
              "displayName": "Bench Press (Barbell)",
              "aliases": ["Bench Press"],
              "exerciseMode": "weight_reps",
              "equipment": "barbell",
              "primaryMuscleGroup": "chest",
              "secondaryMuscleGroups": [],
              "isPickerDefault": true,
              "isHevyLibrary": true
            }
          ]
        }
        """
        let data = Data(manifest.utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("exercise_seed_hidden_test.json")
        try data.write(to: url)

        _ = try importer.importIfNeeded(manifestURL: url, manifestData: data)

        #expect(try store.exercises.fetchSummary(id: "seed-bench-press") == nil)
        #expect(try !store.exercises.listForPicker(search: "Bench Press").contains { $0.id == "seed-bench-press" })
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
