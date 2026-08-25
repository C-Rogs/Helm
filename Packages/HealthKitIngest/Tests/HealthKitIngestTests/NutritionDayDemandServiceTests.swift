import Core
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Nutrition day demand service")
struct NutritionDayDemandServiceTests {
    @Test("explicit override wins over planned training and cardio")
    func overridePriority() throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 8, day: 24)
        try store.plan.replacePlannedWorkouts([plannedWorkout(on: day)])
        let service = NutritionDayDemandService(persistence: store)
        try service.setExplicitOverride(.party, for: day)

        let result = try service.resolve(for: day, plannedCardioDays: [day], ordinaryDemand: .office)

        #expect(result.demand == .party)
        #expect(result.source == .explicitOverride)
    }

    @Test("planned training wins over cardio and ordinary office")
    func trainingPriority() throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 8, day: 25)
        try store.plan.replacePlannedWorkouts([plannedWorkout(on: day)])

        let result = try NutritionDayDemandService(persistence: store)
            .resolve(for: day, plannedCardioDays: [day], ordinaryDemand: .office)

        #expect(result.demand == .training)
        #expect(result.source == .plannedTraining)
    }

    @Test("cardio wins over ordinary office, then clearing override restores inference")
    func cardioAndClear() throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 8, day: 26)
        let service = NutritionDayDemandService(persistence: store)
        try service.setExplicitOverride(.highIntake, for: day)
        try service.clearExplicitOverride(for: day)

        let cardio = try service.resolve(for: day, plannedCardioDays: [day], ordinaryDemand: .office)
        let office = try service.resolve(for: day, ordinaryDemand: .office)

        #expect(cardio.demand == .cardio)
        #expect(cardio.source == .plannedCardio)
        #expect(office.demand == .office)
        #expect(office.source == .ordinary)
    }

    private func plannedWorkout(on day: HelmDay) -> PlannedWorkoutRecord {
        PlannedWorkoutRecord(
            id: "planned-\(day.formatted)",
            helmDay: day,
            status: "pending",
            trainingLoad: 3,
            sessionJSON: "{}"
        )
    }
}
