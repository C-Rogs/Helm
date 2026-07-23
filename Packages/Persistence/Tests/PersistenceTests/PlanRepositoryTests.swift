import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Plan repository")
struct PlanRepositoryTests {
    @Test("mesocycle state round trip")
    func mesocycleStateRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let json = #"{"week":3}"#

        try store.plan.saveMesocycleStateJSON(json)
        let loaded = try store.plan.loadMesocycleStateJSON()

        #expect(loaded == json)
    }

    @Test("planned workouts replace and fetch range")
    func plannedWorkoutRange() throws {
        let store = try PersistenceStore.inMemory()
        let start = HelmDay(year: 2026, month: 7, day: 20)
        let end = HelmDay(year: 2026, month: 7, day: 24)
        let records = [
            PlannedWorkoutRecord(
                id: "w1",
                helmDay: start,
                status: "pending",
                trainingLoad: 80,
                sessionJSON: #"{"id":"w1"}"#
            ),
            PlannedWorkoutRecord(
                id: "w2",
                helmDay: end,
                status: "pending",
                trainingLoad: 90,
                sessionJSON: #"{"id":"w2"}"#
            )
        ]

        try store.plan.replacePlannedWorkouts(records)
        let fetched = try store.plan.fetchPlannedWorkouts(from: start, through: end)

        #expect(fetched.count == 2)
        #expect(fetched.map(\.id).sorted() == ["w1", "w2"])
    }
}
