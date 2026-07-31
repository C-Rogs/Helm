import Foundation
import Testing
@testable import Core

@Suite("Train session progress")
struct TrainSessionProgressTests {
    @Test("header counts match session snapshot")
    func countsMatchSession() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let now = startedAt.addingTimeInterval(754)
        let snapshot = ActiveSessionSnapshot(
            session: WorkoutSessionDraft(
                startedAt: startedAt,
                exercises: [
                    WorkoutSessionExerciseDraft(
                        exerciseID: "bench",
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(setIndex: 0, status: .completed),
                            SetEntryDraft(setIndex: 1, status: .completed),
                            SetEntryDraft(setIndex: 2, status: .planned)
                        ]
                    ),
                    WorkoutSessionExerciseDraft(
                        exerciseID: "row",
                        displayOrder: 1,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(setIndex: 0, status: .planned),
                            SetEntryDraft(setIndex: 1, status: .skipped)
                        ]
                    )
                ]
            ),
            recoveryState: .active
        )

        let progress = TrainSessionProgress.from(snapshot: snapshot, now: now)

        #expect(progress.completedSetCount == 2)
        #expect(progress.totalSetCount == 5)
        #expect(progress.elapsedSeconds == 754)
        #expect(TrainSessionProgressFormatter.elapsedLabel(seconds: progress.elapsedSeconds) == "12:34")
        #expect(TrainSessionProgressFormatter.setCountLabel(
            completed: progress.completedSetCount,
            total: progress.totalSetCount
        ) == "2/5 sets")
    }

    @Test("empty session reports zero sets")
    func emptySession() {
        let snapshot = ActiveSessionSnapshot(
            session: WorkoutSessionDraft(startedAt: .now, exercises: []),
            recoveryState: .active
        )

        let progress = TrainSessionProgress.from(snapshot: snapshot)

        #expect(progress.completedSetCount == 0)
        #expect(progress.totalSetCount == 0)
    }
}
