import Core
import Foundation
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Schedule drift runtime")
struct ScheduleDriftRuntimeTests {
    private let calendar = Calendar(identifier: .iso8601)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> HelmDay {
        HelmDay(year: y, month: m, day: d)
    }

    @Test("late completion shifts planned record and emits drift note")
    func lateCompletionShift() {
        let plannedDay = day(2026, 7, 20)
        let actualDay = day(2026, 7, 21)
        let record = PlannedWorkoutRecord(
            id: "planned-2026-7-20",
            helmDay: plannedDay,
            status: "pending",
            trainingLoad: 3,
            sessionJSON: """
            {"splitLabel":"Push","splitKind":"push","targetMuscles":["chest"],"scheduleNotes":[]}
            """
        )
        let pushMuscles = ExerciseMuscleMap(
            exerciseID: "bench",
            contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0, tier: .primary)]
        )
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [
                WorkoutSession(
                    helmDay: actualDay,
                    startedAt: Date(),
                    sets: [
                        LoggedSet(
                            exerciseID: "bench",
                            sequence: 1,
                            reps: 8,
                            completedAt: Date(),
                            setType: .normal
                        )
                    ]
                )
            ],
            weekStart: day(2026, 7, 20)
        )

        let result = ScheduleDriftResolver.resolveAndApply(
            records: [record],
            history: history,
            muscleMaps: ["bench": pushMuscles],
            calendar: calendar
        )

        #expect(result.records.first?.status == PlannedSessionStatus.shifted.rawValue)
        #expect(result.driftNotes.isEmpty == false)
    }

    @Test("history fingerprint changes when session logged")
    func historyFingerprintChanges() {
        let weekStart = day(2026, 7, 20)
        let empty = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        let logged = PrescriptionHistory(
            loggedSets: [],
            sessions: [
                WorkoutSession(
                    helmDay: weekStart,
                    startedAt: Date(),
                    sets: [
                        LoggedSet(
                            exerciseID: "bench",
                            sequence: 1,
                            reps: 8,
                            completedAt: Date(),
                            setType: .normal
                        )
                    ]
                )
            ],
            weekStart: weekStart
        )
        let map = ExerciseMuscleMap(
            exerciseID: "bench",
            contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0, tier: .primary)]
        )
        let muscleMaps = ["bench": map]
        let before = PrescriptionHistoryBuilder.historyFingerprint(
            empty,
            through: weekStart,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        let after = PrescriptionHistoryBuilder.historyFingerprint(
            logged,
            through: weekStart,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        #expect(before != after)
    }
}
