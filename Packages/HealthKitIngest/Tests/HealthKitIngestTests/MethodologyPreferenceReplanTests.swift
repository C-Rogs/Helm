import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Methodology preference re-plan")
struct MethodologyPreferenceReplanTests {
    @Test("preferences persist through memory profile")
    func preferencesPersist() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = PlanPrescriptionEngine(persistence: store)

        try await engine.saveMethodologyPreferences(
            MethodologyPreferences(allowedEquipment: ["dumbbell"], selectionBias: .stretch)
        )

        let profile = try store.memoryProfile.load()
        let parsed = MethodologyPreferences.parse(from: profile.preferences)
        #expect(parsed.preferences.allowedEquipment == ["dumbbell"])
        #expect(parsed.preferences.selectionBias == .stretch)
    }

    @Test("equipment preference changes selected exercise")
    func equipmentPreferenceReplans() async throws {
        let store = try PersistenceStore.inMemory()
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("exercise_seed_methodology-\(UUID().uuidString).json")
        let document = ExerciseSeedDocument(
            seedVersion: 99,
            placeholder: true,
            exercises: [
                ExerciseSeedEntry(
                    id: "method-bench",
                    canonicalName: "bench press (barbell)",
                    displayName: "Bench Press (Barbell)",
                    aliases: ["Bench Press"],
                    exerciseMode: .weightReps,
                    equipment: "barbell",
                    primaryMuscleGroup: "chest",
                    secondaryMuscleGroups: ["triceps"],
                    isPickerDefault: true
                ),
                ExerciseSeedEntry(
                    id: "method-db-press",
                    canonicalName: "dumbbell press",
                    displayName: "Dumbbell Press",
                    aliases: ["DB Press"],
                    exerciseMode: .weightReps,
                    equipment: "dumbbell",
                    primaryMuscleGroup: "chest",
                    secondaryMuscleGroups: ["triceps"],
                    isPickerDefault: true
                )
            ]
        )
        try JSONEncoder().encode(document).write(to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        _ = try await store.importExerciseSeedIfNeeded(manifestURL: fixtureURL)
        try store.trainingPlan.save(.default)

        let engine = PlanPrescriptionEngine(persistence: store)
        let day = HelmDay(year: 2026, month: 7, day: 22)

        try await engine.saveMethodologyPreferences(
            MethodologyPreferences(allowedEquipment: ["barbell"])
        )
        let barbellSession = try await engine.computeSession(for: day, readiness: nil)

        try await engine.saveMethodologyPreferences(
            MethodologyPreferences(allowedEquipment: ["dumbbell"])
        )
        let dumbbellSession = try await engine.computeSession(for: day, readiness: nil)

        let barbellChest = barbellSession.exercises.first { $0.exerciseID == "method-bench" }
        let dumbbellChest = dumbbellSession.exercises.first { $0.exerciseID == "method-db-press" }
        #expect(barbellChest != nil)
        #expect(dumbbellChest != nil)
    }
}
