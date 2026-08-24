import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Plan builder session store")
struct PlanBuilderSessionStoreTests {
    @Test("round trip interview, selection, and options")
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
            selectedCandidateIndex: 1,
            options: [
                StoredPlanBuilderOption(encodedCandidate: #"{"id":"balanced"}"#, encodedCopy: #"{"candidateID":"balanced","schemaVersion":"plan_option_cards.v1"}"#)
            ]
        )

        try store.planBuilderSession.save(session)
        let loaded = try store.planBuilderSession.load()

        #expect(loaded == session)
    }

    @Test("legacy JSON without options decodes with empty options")
    func legacyDecode() throws {
        let store = try PersistenceStore.inMemory()
        try store.planBuilderSession.save(StoredPlanBuilderSession(interview: PlanBuilderInterview()))
        // Rewrite the row to a legacy shape lacking the options key.
        try store.poolForTesting.write { db in
            try db.execute(
                sql: "UPDATE plan_builder_session SET session_json = ? WHERE id = ?",
                arguments: [#"{"interview":{"confirmed_maintenance_kcal":null,"days_per_week":3,"emphasis":null,"experience_raw":"intermediate","progression_goal":"hypertrophy","session_duration_minutes":60,"uses_computed_estimate":true},"selected_candidate_index":null}"#, 1]
            )
        }
        let loaded = try store.planBuilderSession.load()
        #expect(loaded?.options.isEmpty == true)
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
