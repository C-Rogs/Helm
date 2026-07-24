import Core
import Foundation
import Testing
@testable import HealthKitIngest
@testable import PlanKit

@Suite("Workout finish summary")
struct WorkoutFinishSummaryBuilderTests {
    @Test("Builds summary from fixture session data")
    func buildsFromFixtureSession() {
        let completedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let session = WorkoutSessionDraft(
            id: "session-finish",
            startedAt: completedAt.addingTimeInterval(-3_240),
            endedAt: completedAt,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: "bench",
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 0,
                            mass: Mass(kilograms: 100),
                            reps: 5,
                            rpe: 8,
                            completedAt: completedAt
                        ),
                        SetEntryDraft(
                            setIndex: 1,
                            mass: Mass(kilograms: 100),
                            reps: 5,
                            rpe: 8.5,
                            completedAt: completedAt
                        ),
                    ]
                ),
            ]
        )

        let summary = WorkoutFinishSummaryBuilder.build(
            session: session,
            sessionMuscleCredits: [.chest: 2],
            weeklyTotalsAfter: [.chest: 12],
            landmarks: [.chest: VolumeLandmarks(mev: 10, mrv: 20)]
        )

        #expect(summary.setCount == 2)
        #expect(summary.totalVolumeKilograms == 1_000)
        #expect(summary.estimatedTRIMP > 0)
        #expect(summary.durationMinutes == 54)
        #expect(summary.muscleMovements.count == 1)
        #expect(summary.muscleMovements[0].setsBefore == 10)
        #expect(summary.muscleMovements[0].setsAfter == 12)
        #expect(!summary.readinessTeaser.isEmpty)
    }

    @Test("Readiness teaser scales with session load")
    func readinessTeaserTiers() {
        #expect(
            WorkoutFinishSummaryBuilder.readinessTeaser(setCount: 20, volumeKilograms: 9_000)
                .contains("Heavy")
        )
        #expect(
            WorkoutFinishSummaryBuilder.readinessTeaser(setCount: 12, volumeKilograms: 5_000)
                .contains("Moderate")
        )
        #expect(
            WorkoutFinishSummaryBuilder.readinessTeaser(setCount: 6, volumeKilograms: 2_000)
                .contains("Light")
        )
    }
}
