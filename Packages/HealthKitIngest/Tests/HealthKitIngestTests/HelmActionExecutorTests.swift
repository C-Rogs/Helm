import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("HelmActionExecutor")
struct HelmActionExecutorTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private let benchPressID = "bench_press"
    private let inclineDBPressID = "incline_db_press"

    @Test("coach food log payload writes through run()")
    func coachFoodLogWritesMeal() async throws {
        let store = try PersistenceStore.inMemory()
        let executor = HelmActionExecutor(persistence: store, calendar: calendar)
        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Logged dinner.",
            action: .log,
            description: "Quick dinner",
            bucket: "dinner",
            caloriesKcal: 700,
            proteinG: 40,
            carbsG: 60,
            fatG: 20,
            helmDay: "2023-11-15"
        )

        let result = try await executor.run(.meal(.fromCoachPayload(payload, now: loggedAt)))

        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        #expect(result.nutritionDay == helmDay)
        #expect(result.sideEffects == [.refreshNutrition(helmDay)])
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].bucket == .dinner)
        #expect(meals[0].energy?.kilocalories == 700)
    }

    @Test("delete meal command removes the row")
    func deleteMealRemovesRow() async throws {
        let store = try PersistenceStore.inMemory()
        let meals = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let executor = HelmActionExecutor(
            manualMealService: meals,
            persistence: store,
            mealRepeatService: MealRepeatService(store: store, manualMealService: meals),
            calendar: calendar
        )
        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let at = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))
        )
        let saved = try await meals.logQuickAdd(
            kilocalories: 400,
            label: "Snack",
            bucket: .snacks,
            loggedAt: at,
            helmDay: helmDay
        )
        let mealID = try #require(UUID(uuidString: saved.mealID))

        _ = try await executor.run(.meal(.deleteMeal(mealID: mealID, helmDay: helmDay)))
        #expect(try store.nutrition.fetchMeals(for: helmDay).isEmpty)
    }

    @Test("copy meal uses MealRepeatService")
    func copyMealCopiesBucket() async throws {
        let store = try PersistenceStore.inMemory()
        let meals = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let executor = HelmActionExecutor(
            manualMealService: meals,
            persistence: store,
            mealRepeatService: MealRepeatService(store: store, manualMealService: meals),
            calendar: calendar
        )
        let source = HelmDay(year: 2023, month: 11, day: 14)
        let target = HelmDay(year: 2023, month: 11, day: 15)
        let at = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 12))
        )
        _ = try await meals.logQuickAdd(
            kilocalories: 500,
            label: "Lunch",
            bucket: .lunch,
            loggedAt: at,
            helmDay: source
        )

        let result = try await executor.run(
            .copyMeal(HelmCopyMealCommand(
                sourceDay: source,
                sourceBucket: .lunch,
                targetDay: target
            ))
        )
        #expect(result.nutritionDay == target)
        #expect(try store.nutrition.fetchMeals(for: target).count == 1)
    }

    @Test("session adjust through executor applies swap")
    func sessionAdjustAppliesSwap() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let executor = HelmActionExecutor(persistence: store)
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

        let result = try await executor.run(
            .applySessionAdjustment(HelmSessionAdjustmentCommand(
                payload: payload,
                snapshot: snapshot,
                excludedExerciseIDs: []
            ))
        )

        #expect(result.sessionAdjustment?.banner.toLabel == "Incline DB Press")
        #expect(result.sideEffects == [.refreshPrescription])
        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        #expect(refreshed?.session.exercises.first?.exerciseID == inclineDBPressID)
    }

    @Test("advisory session payload still fails through executor")
    func advisorySessionFails() async throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)
        let snapshot = try await startBenchSession(in: store)
        let executor = HelmActionExecutor(persistence: store)
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Stay at 80 kg today.",
            operations: []
        )

        do {
            _ = try await executor.run(
                .applySessionAdjustment(HelmSessionAdjustmentCommand(
                    payload: payload,
                    snapshot: snapshot,
                    excludedExerciseIDs: []
                ))
            )
            Issue.record("Expected noApplicableChange for advisory payload")
        } catch InSessionCoachError.noApplicableChange {}

        let refreshed = try store.activeSessions.fetchActiveSnapshot(at: Date())
        #expect(refreshed?.session.exercises.first?.exerciseID == benchPressID)
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
            id: inclineDBPressID,
            canonicalName: "incline dumbbell press",
            displayName: "Incline DB Press",
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
                    targetRepMax: 10,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                )
            ]
        )
        return try await engine.startFromPrescription(prescription)
    }
}
