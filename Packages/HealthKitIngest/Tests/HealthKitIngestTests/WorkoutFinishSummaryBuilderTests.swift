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

    @Test("Empty heart rate series by default")
    func emptyHeartRateByDefault() {
        let summary = WorkoutFinishSummary(
            setCount: 1,
            totalVolumeKilograms: 100,
            estimatedTRIMP: 10,
            durationMinutes: 5,
            muscleMovements: [],
            readinessTeaser: "Light session; minimal readiness impact."
        )
        #expect(!summary.hasHeartRateSeries)
        #expect(summary.heartRateSamples.isEmpty)
        #expect(summary.setMarkers.isEmpty)
    }

    @Test("Attaches heart rate samples and set markers")
    func attachesHeartRateSeries() {
        let base = WorkoutFinishSummary(
            setCount: 2,
            totalVolumeKilograms: 500,
            estimatedTRIMP: 40,
            durationMinutes: 20,
            muscleMovements: [],
            readinessTeaser: "Moderate load; readiness should hold steady."
        )
        let summary = base.withHeartRate(
            samples: [
                SessionHeartRateSample(offsetSeconds: 0, bpm: 120),
                SessionHeartRateSample(offsetSeconds: 60, bpm: 140)
            ],
            setMarkers: [SessionSetMarker(offsetSeconds: 60, setNumber: 1)]
        )
        #expect(summary.hasHeartRateSeries)
        #expect(summary.heartRateSamples.map(\.bpm) == [120, 140])
        #expect(summary.setMarkers.map(\.setNumber) == [1])
    }
}
