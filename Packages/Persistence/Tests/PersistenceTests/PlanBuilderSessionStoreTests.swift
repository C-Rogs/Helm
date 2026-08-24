import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Plan builder session store")
struct PlanBuilderSessionStoreTests {
    @Test("round trip interview and selection")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let session = StoredPlanBuilderSession(
            interview: PlanBuilderInterview(
                confirmedMaintenanceKcal: 2800,
                usesComputedEstimate: false,
                daysPerWeek: 4,
                sessionDurationMinutes: 45,
                progressionGoal: .strength,
                emphasis: "arms"
            ),
            selectedCandidateIndex: 1
        )

        try store.planBuilderSession.save(session)
        let loaded = try store.planBuilderSession.load()

        #expect(loaded == session)
    }

    @Test("load returns nil when empty and clear removes row")
    func loadAndClear() throws {
        let store = try PersistenceStore.inMemory()
        #expect(try store.planBuilderSession.load() == nil)

        try store.planBuilderSession.save(StoredPlanBuilderSession(interview: PlanBuilderInterview()))
        #expect(try store.planBuilderSession.load() != nil)

        try store.planBuilderSession.clear()
        #expect(try store.planBuilderSession.load() == nil)
    }
}

@Suite("Training plan settings days per week")
struct TrainingPlanSettingsDaysTests {
    @Test("legacy JSON without daysPerWeek defaults to 3")
    func legacyDecode() throws {
        let json = """
        {"experienceRaw":"novice","phaseGoal":{"phase":"maintain"}}
        """
        let decoded = try JSONDecoder().decode(StoredTrainingPlanSettings.self, from: Data(json.utf8))
        #expect(decoded.daysPerWeek == 3)
    }

    @Test("daysPerWeek clamps to sane range")
    func clamped() {
        let low = StoredTrainingPlanSettings(daysPerWeek: 1)
        let high = StoredTrainingPlanSettings(daysPerWeek: 9)
        #expect(low.daysPerWeek == 2)
        #expect(high.daysPerWeek == 6)
    }
}
