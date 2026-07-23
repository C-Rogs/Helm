import Core
import Testing
@testable import Persistence

@Suite("Training plan settings store")
struct TrainingPlanSettingsStoreTests {
    @Test("round trip phase goal and experience")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let settings = StoredTrainingPlanSettings(
            phaseGoal: PhaseGoal(phase: .cut, weeklyRateKg: 0.5, emphasis: "v-taper"),
            experienceRaw: "advanced"
        )

        try store.trainingPlan.save(settings)
        let loaded = try store.trainingPlan.load()

        #expect(loaded == settings)
    }

    @Test("defaults when unset")
    func defaultsWhenUnset() throws {
        let store = try PersistenceStore.inMemory()
        let loaded = try store.trainingPlan.load()
        #expect(loaded == .default)
    }
}
