import Core
import Foundation
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Session split planner")
struct SessionSplitPlannerTests {
    @Test("split labels map push pull legs")
    func splitLabels() {
        #expect(SessionSplitPlanner.splitLabel(for: [.chest, .shoulders, .triceps], emphasis: nil) == "Push")
        #expect(SessionSplitPlanner.splitLabel(for: [.back, .biceps], emphasis: nil) == "Pull")
        #expect(SessionSplitPlanner.splitLabel(for: [.quads, .hamstrings, .glutes], emphasis: nil) == "Legs")
    }

    @Test("emphasis does not override weekday split rotation")
    func emphasisDoesNotOverrideSplit() {
        let day = HelmDay(year: 2026, month: 7, day: 28)
        let muscles = SessionSplitPlanner.targetMuscles(for: day, emphasis: "Arms")
        #expect(muscles.contains(.chest) || muscles.contains(.back) || muscles.contains(.quads))
        #expect(SessionSplitPlanner.splitKind(for: day, emphasis: "Arms") != .armFocus)
    }
}

@Suite("Schedule planner")
struct SchedulePlannerTests {
    @Test("next split follows completed sessions this week")
    func nextSplitAfterPush() {
        let weekStart = HelmDay(year: 2026, month: 7, day: 27)
        let pushDay = weekStart
        let today = weekStart.adding(days: 1)
        let history = PrescriptionHistory(
            loggedSets: [
                LoggedSet(
                    exerciseID: "bench_press",
                    sequence: 1,
                    mass: Mass(kilograms: 80),
                    reps: 8,
                    completedAt: Date()
                )
            ],
            sessions: [
                WorkoutSession(
                    id: UUID(),
                    helmDay: pushDay,
                    startedAt: Date(),
                    finishedAt: Date(),
                    sets: [
                        LoggedSet(
                            exerciseID: "bench_press",
                            sequence: 1,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: Date()
                        )
                    ]
                )
            ],
            weekStart: weekStart
        )
        let muscleMaps: [String: ExerciseMuscleMap] = [
            "bench_press": ExerciseMuscleMap(exerciseID: "bench_press", contributions: [
                ExerciseMuscleContribution(muscle: .chest, fraction: 0.7),
                ExerciseMuscleContribution(muscle: .triceps, fraction: 0.3)
            ])
        ]

        let result = SchedulePlanner.plan(
            for: today,
            emphasis: nil,
            history: history,
            muscleMaps: muscleMaps
        )

        #expect(result.splitKind == .pull)
    }

    @Test("planned workout records encode decodable week payload")
    func plannedWorkoutRecordsPayload() {
        let start = HelmDay(year: 2026, month: 7, day: 28)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [],
            weekStart: HelmDay(year: 2026, month: 7, day: 27)
        )

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: [:]
        )

        #expect(records.count == 3)
        let payload = PlannedWorkoutSessionDecoder.decode(from: records[0].sessionJSON)
        #expect(payload?.splitLabel.isEmpty == false)
    }

    @Test("training day offsets space three sessions across the week")
    func trainingDayOffsetsSpacing() {
        #expect(SchedulePlanner.trainingDayOffsets(sessionsPerWeek: 3) == [0, 2, 4])
    }

    @Test("seven day projection plans three spaced sessions from empty history")
    func plannedWorkoutRecordsRotateFromEmptyHistory() {
        let start = HelmDay(year: 2026, month: 7, day: 28)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [],
            weekStart: HelmDay(year: 2026, month: 7, day: 27)
        )

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: [:]
        )

        let labels = records.compactMap { PlannedWorkoutSessionDecoder.decode(from: $0.sessionJSON)?.splitLabel }
        #expect(records.count == 3)
        #expect(labels == ["Push", "Pull", "Legs"])
        #expect(Set(labels) == Set(["Push", "Pull", "Legs"]))
    }

    @Test("seven day projection advances after push logged this week")
    func plannedWorkoutRecordsAdvanceAfterPush() {
        let weekStart = HelmDay(year: 2026, month: 7, day: 27)
        let pushDay = weekStart
        let start = weekStart.adding(days: 1)
        let history = PrescriptionHistory(
            loggedSets: [
                LoggedSet(
                    exerciseID: "bench_press",
                    sequence: 1,
                    mass: Mass(kilograms: 80),
                    reps: 8,
                    completedAt: Date()
                )
            ],
            sessions: [
                WorkoutSession(
                    id: UUID(),
                    helmDay: pushDay,
                    startedAt: Date(),
                    finishedAt: Date(),
                    sets: [
                        LoggedSet(
                            exerciseID: "bench_press",
                            sequence: 1,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: Date()
                        )
                    ]
                )
            ],
            weekStart: weekStart
        )
        let muscleMaps: [String: ExerciseMuscleMap] = [
            "bench_press": ExerciseMuscleMap(exerciseID: "bench_press", contributions: [
                ExerciseMuscleContribution(muscle: .chest, fraction: 0.7),
                ExerciseMuscleContribution(muscle: .triceps, fraction: 0.3)
            ])
        ]

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: muscleMaps
        )

        let labels = records.compactMap { PlannedWorkoutSessionDecoder.decode(from: $0.sessionJSON)?.splitLabel }
        #expect(records.count == 3)
        #expect(labels == ["Pull", "Legs", "Push"])
        #expect(Set(labels).count > 1)
    }

    @Test("projection restarts rotation at calendar week boundary")
    func plannedWorkoutRecordsRestartAtWeekBoundary() {
        let weekStart = HelmDay(year: 2026, month: 7, day: 27)
        let pushDay = weekStart
        let start = HelmDay(year: 2026, month: 7, day: 31)
        let history = PrescriptionHistory(
            loggedSets: [
                LoggedSet(
                    exerciseID: "bench_press",
                    sequence: 1,
                    mass: Mass(kilograms: 80),
                    reps: 8,
                    completedAt: Date()
                )
            ],
            sessions: [
                WorkoutSession(
                    id: UUID(),
                    helmDay: pushDay,
                    startedAt: Date(),
                    finishedAt: Date(),
                    sets: [
                        LoggedSet(
                            exerciseID: "bench_press",
                            sequence: 1,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: Date()
                        )
                    ]
                )
            ],
            weekStart: weekStart
        )
        let muscleMaps: [String: ExerciseMuscleMap] = [
            "bench_press": ExerciseMuscleMap(exerciseID: "bench_press", contributions: [
                ExerciseMuscleContribution(muscle: .chest, fraction: 0.7),
                ExerciseMuscleContribution(muscle: .triceps, fraction: 0.3)
            ])
        ]

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: muscleMaps
        )

        let labels = records.compactMap { PlannedWorkoutSessionDecoder.decode(from: $0.sessionJSON)?.splitLabel }
        #expect(records.count == 3)
        #expect(labels[0] == "Pull")
        #expect(labels[1] == "Push")
        #expect(labels[2] == "Pull")
    }

    @Test("seven day horizon caps total projected sessions")
    func plannedWorkoutHorizonSessionCap() {
        let start = HelmDay(year: 2026, month: 7, day: 31)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [],
            weekStart: HelmDay(year: 2026, month: 7, day: 27)
        )

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: [:]
        )

        #expect(records.count == SchedulePlanner.defaultSessionsPerWeek)
    }

    @Test("projection notes only cite logged sessions")
    func plannedWorkoutProjectionNotesCiteLoggedSessionsOnly() {
        let start = HelmDay(year: 2026, month: 7, day: 28)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [],
            weekStart: HelmDay(year: 2026, month: 7, day: 27)
        )

        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: start,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: [:]
        )

        guard records.count >= 2 else {
            Issue.record("Expected at least two projected training days")
            return
        }
        let secondDayNotes = PlannedWorkoutSessionDecoder.decode(from: records[1].sessionJSON)?.scheduleNotes ?? []
        #expect(secondDayNotes.contains(where: { $0.contains("already logged") }) == false)
    }
}

@Suite("Prescription day store")
struct PrescriptionDayStoreTests {
    @Test("round trips adjusted prescription")
    func roundTrip() {
        let day = HelmDay(year: 2026, month: 7, day: 28)
        let prescription = SessionPrescription(
            helmDay: day,
            title: "Pull",
            exercises: [
                PrescribedExercise(exerciseID: "row", order: 0, targetSets: 3, targetRepMin: 8, targetRepMax: 10)
            ]
        )
        PrescriptionDayStore.save(prescription, for: day)
        let loaded = PrescriptionDayStore.load(for: day)
        #expect(loaded?.title == "Pull")
        #expect(loaded?.exercises.count == 1)
        PrescriptionDayStore.clear(for: day)
        #expect(PrescriptionDayStore.load(for: day) == nil)
    }
}
