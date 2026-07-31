import CoachLLM
import Core
import Foundation
import Persistence
import ReadinessKit
import Testing
@testable import HealthKitIngest

@Suite("CoachContextAssembler")
struct CoachContextAssemblerTests {
    private let day = HelmDay(year: 2026, month: 7, day: 22)
    private let previous = HelmDay(year: 2026, month: 7, day: 21)

    @Test("includes body composition in recent days and stable baselines")
    func includesBodyComposition() throws {
        let store = try PersistenceStore.inMemory()
        let measuredAt = Calendar.current.date(from: DateComponents(
            timeZone: .current,
            year: 2026,
            month: 7,
            day: 22,
            hour: 8
        ))!

        try store.bodyComposition.upsert(
            BodyComposition(
                helmDay: previous,
                mass: Mass(kilograms: 82.4),
                measuredAt: measuredAt
            )
        )

        let context = try CoachContextAssembler.assemble(from: store, endingAt: day, lookbackDays: 7)

        #expect(context.readinessBaselines.contains("2026-07-21 weight=82.4kg"))
        #expect(context.recent.count == 1)
        #expect(context.recent[0].text.contains("weight=82.4kg"))
    }

    @Test("assembles recent days from persisted health rows")
    func assemblesRecentDays() throws {
        let store = try PersistenceStore.inMemory()

        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: previous,
                hrvSDNN: DurationMs(milliseconds: 49),
                restingHeartRate: 52,
                priorDayTRIMP: 42
            )
        )
        try store.readiness.upsertScore(
            helmDay: previous,
            scoreJSON: """
            {"score":58,"effectiveHRVMilliseconds":49.0,"restingHeartRate":52}
            """
        )
        try store.readiness.upsertBaseline(
            stateJSON: """
            {"hrvChronic":{"mean":52.1,"robustSigma":4.0},"restingHR":{"mean":51.0,"robustSigma":2.0},"seededNightCount":28}
            """
        )

        let context = try CoachContextAssembler.assemble(from: store, endingAt: day, lookbackDays: 7)

        #expect(context.readinessBaselines.contains("hrvChronicMs=52.1"))
        #expect(context.readinessBaselines.contains("seededNights=28"))
        #expect(context.recent.count == 1)
        #expect(context.recent[0].helmDay == previous)
        #expect(context.recent[0].text.contains("readiness=58"))
        #expect(context.recent[0].text.contains("hrv=49ms"))
        #expect(context.recent[0].text.contains("trimp=42"))
    }

    @Test("assembles recent workouts block with full set detail")
    func assemblesRecentWorkoutsBlock() throws {
        let store = try PersistenceStore.inMemory()
        let squatID = "exercise-squat"
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps
        )

        let completedAt = Calendar.current.date(from: DateComponents(
            timeZone: .current,
            year: 2026,
            month: 7,
            day: 22,
            hour: 18
        ))!
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "session-recent",
                title: "Leg Day",
                startedAt: completedAt,
                endedAt: completedAt,
                exercises: [
                    WorkoutSessionExerciseDraft(
                        id: "wse-1",
                        exerciseID: squatID,
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                id: "set-1",
                                setIndex: 0,
                                mass: Mass(kilograms: 100),
                                reps: 5,
                                completedAt: completedAt
                            )
                        ]
                    )
                ]
            )
        )

        let context = try CoachContextAssembler.assemble(from: store, endingAt: day, lookbackDays: 7)

        #expect(context.recentWorkouts.contains("Leg Day"))
        #expect(context.recentWorkouts.contains("Squat (Barbell)"))
        #expect(context.recentWorkouts.contains("100kg x 5"))
    }

    @Test("includes training plan snapshot with verbatim emphasis")
    func includesTrainingPlanSnapshot() throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(
            StoredTrainingPlanSettings(
                phaseGoal: PhaseGoal(phase: .maintain, emphasis: "calves"),
                experienceRaw: TrainingExperience.intermediate.rawValue
            )
        )

        let context = try CoachContextAssembler.assemble(from: store, endingAt: day, lookbackDays: 7)

        #expect(context.trainingPlanSnapshot.contains("emphasis=\"calves\""))
        #expect(context.trainingPlanSnapshot.contains("engine_note=split_rotation_only"))
        #expect(context.trainingPlanSnapshot.contains("rolling_7d_hard_sets:"))
    }
}
