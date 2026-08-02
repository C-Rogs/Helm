import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("FoodLogCommand")
struct FoodLogCommandTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    @Test("parses food_log payload from assistant text")
    func parsesPayload() {
        let text = """
        Logged.
        {"schemaVersion":"food_log.v1","reply":"Logged lunch.","action":"log","description":"Salad","bucket":"lunch","caloriesKcal":320,"proteinG":20,"carbsG":30,"fatG":8,"helmDay":"2023-11-15"}
        """
        let payload = FoodLogPayloadParser.parse(from: text)
        #expect(payload?.schemaVersion == CoachOutputSchemaVersion.foodLogV1.rawValue)
        #expect(payload?.action == .log)
        #expect(payload?.caloriesKcal == 320)
    }

    @Test("flags malformed food_log block when decode fails")
    func flagsMalformedBlock() {
        let text = """
        Ready.
        {"schemaVersion":"food_log.v1","reply":"ok","action":"log","caloriesKcal":{"bad":true}}
        """
        #expect(FoodLogPayloadParser.parse(from: text) == nil)
        #expect(FoodLogPayloadParser.hasMalformedBlock(in: text))
    }

    @Test("log action writes meal via ManualMealService")
    func logActionWritesMeal() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let applier = FoodLogCommandApplier(
            manualMealService: service,
            persistence: store,
            calendar: calendar
        )

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

        try await applier.apply(payload, now: loggedAt)

        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].bucket == .dinner)
        #expect(meals[0].source == .quickAdd)
        #expect(meals[0].energy?.kilocalories == 700)
    }

    @Test("delete action removes meal")
    func deleteActionRemovesMeal() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let applier = FoodLogCommandApplier(
            manualMealService: service,
            persistence: store,
            calendar: calendar
        )
        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))
        )

        let saved = try await service.logQuickAdd(
            kilocalories: 400,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            helmDay: helmDay
        )
        let mealID = try #require(UUID(uuidString: saved.mealID))

        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Removed snack.",
            action: .delete,
            mealID: mealID.uuidString.lowercased()
        )

        try await applier.apply(payload)

        #expect(try store.nutrition.fetchMeals(for: helmDay).isEmpty)
    }

    @Test("preview describes log action")
    func previewDescribesLog() {
        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Logged.",
            action: .log,
            description: "Oats",
            bucket: "breakfast",
            caloriesKcal: 350
        )
        let preview = FoodLogCommandPreview.preview(for: payload)
        #expect(preview.title == "Log breakfast")
        #expect(preview.detail.contains("Oats"))
    }

    @Test("log action persists locally when HealthKit write fails")
    func logActionPersistsWhenHealthKitFails() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        mockHK.mealSaveShouldFail = true
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let applier = FoodLogCommandApplier(
            manualMealService: service,
            persistence: store,
            calendar: calendar
        )

        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Logged breakfast.",
            action: .log,
            description: "Example breakfast",
            bucket: "breakfast",
            caloriesKcal: 420,
            proteinG: 25,
            carbsG: 45,
            fatG: 12,
            helmDay: "2026-08-01"
        )

        try await applier.apply(payload, now: loggedAt)

        let helmDay = HelmDay(year: 2026, month: 8, day: 1)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].bucket == .breakfast)
        #expect(meals[0].energy?.kilocalories == 420)
        #expect(mockHK.savedMealIDs.isEmpty)
    }

    @Test("yesterday breakfast example macros lands on helmDay not today")
    func yesterdayBreakfastUsesHelmDay() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let applier = FoodLogCommandApplier(
            manualMealService: service,
            persistence: store,
            calendar: calendar
        )
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 10))
        )

        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Logged example breakfast.",
            action: .log,
            description: "Example breakfast macros",
            bucket: "breakfast",
            caloriesKcal: 380,
            proteinG: 22,
            carbsG: 40,
            fatG: 10,
            helmDay: "2026-08-01"
        )

        try await applier.apply(payload, now: now)

        let yesterday = HelmDay(year: 2026, month: 8, day: 1)
        let today = HelmDay(year: 2026, month: 8, day: 2)
        #expect(try store.nutrition.fetchMeals(for: yesterday).count == 1)
        #expect(try store.nutrition.fetchMeals(for: today).isEmpty)
    }

    @Test("bulk delete by helmDay removes all meals")
    func bulkDeleteByHelmDay() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let applier = FoodLogCommandApplier(
            manualMealService: service,
            persistence: store,
            calendar: calendar
        )
        let helmDay = HelmDay(year: 2026, month: 8, day: 1)
        let at = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))
        )
        _ = try await service.logQuickAdd(
            kilocalories: 300,
            label: "Breakfast",
            bucket: .breakfast,
            loggedAt: at,
            helmDay: helmDay
        )
        _ = try await service.logQuickAdd(
            kilocalories: 500,
            label: "Lunch",
            bucket: .lunch,
            loggedAt: at.addingTimeInterval(3600),
            helmDay: helmDay
        )
        #expect(try store.nutrition.fetchMeals(for: helmDay).count == 2)

        let payload = FoodLogPayload(
            schemaVersion: CoachOutputSchemaVersion.foodLogV1.rawValue,
            reply: "Deleted yesterday.",
            action: .delete,
            helmDay: "2026-08-01"
        )
        try await applier.apply(payload)
        #expect(try store.nutrition.fetchMeals(for: helmDay).isEmpty)
    }

    @Test("mealNotFound has readable description")
    func mealNotFoundReadable() {
        #expect(ManualMealError.mealNotFound.errorDescription?.contains("not found") == true)
        #expect(ManualMealError.nothingToDelete.errorDescription?.contains("No meals") == true)
    }
}
