import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Nutrition day demand overrides")
struct NutritionDayDemandOverrideRepositoryTests {
    @Test("override round trips, ranges, replaces, and deletes")
    func lifecycle() throws {
        let store = try PersistenceStore.inMemory()
        let monday = HelmDay(year: 2026, month: 8, day: 24)
        let tuesday = monday.adding(days: 1)
        let timestamp = Date(timeIntervalSince1970: 1_777_000_000)

        try store.nutritionDayDemandOverrides.save(
            NutritionDayDemandOverride(helmDay: monday, demand: .social, updatedAt: timestamp)
        )
        try store.nutritionDayDemandOverrides.save(
            NutritionDayDemandOverride(helmDay: tuesday, demand: .party, updatedAt: timestamp)
        )
        try store.nutritionDayDemandOverrides.save(
            NutritionDayDemandOverride(helmDay: monday, demand: .office, updatedAt: timestamp)
        )

        #expect(try store.nutritionDayDemandOverrides.fetch(for: monday)?.demand == .office)
        #expect(try store.nutritionDayDemandOverrides.fetch(from: monday, through: tuesday).map(\.demand) == [.office, .party])

        try store.nutritionDayDemandOverrides.delete(for: monday)
        #expect(try store.nutritionDayDemandOverrides.fetch(for: monday) == nil)
    }
}
