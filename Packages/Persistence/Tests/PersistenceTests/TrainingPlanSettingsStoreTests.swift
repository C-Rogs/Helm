import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Training plan settings store")
struct TrainingPlanSettingsStoreTests {
    @Test("round trip phase goal and experience")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let settings = StoredTrainingPlanSettings(
            phaseGoal: PhaseGoal(phase: .cut, weeklyRateKg: 0.5, emphasis: "v-taper"),
            experienceRaw: "advanced",
            programTemplateRaw: "ppl",
            sessionDurationMinutes: 45
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
        #expect(loaded.programTemplateRaw == "ppl")
        #expect(loaded.sessionDurationMinutes == 60)
    }

    @Test("legacy JSON without session shape fields still loads")
    func legacyDecode() throws {
        let json = """
        {"experienceRaw":"novice","phaseGoal":{"phase":"maintain"}}
        """
        let decoded = try JSONDecoder().decode(StoredTrainingPlanSettings.self, from: Data(json.utf8))
        #expect(decoded.experienceRaw == "novice")
        #expect(decoded.programTemplateRaw == "ppl")
        #expect(decoded.sessionDurationMinutes == 60)
        #expect(decoded.dayKindRotationRaw.isEmpty)
    }
}
