import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("In-session coach context")
struct InSessionCoachContextBuilderTests {
    @Test("context includes logged mass reps and RPE")
    func loggedSetNumbers() {
        let snapshot = ActiveSessionSnapshot(
            session: WorkoutSessionDraft(
                startedAt: Date(),
                status: .active,
                exercises: [
                    WorkoutSessionExerciseDraft(
                        exerciseID: "bench_press",
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                setIndex: 0,
                                status: .completed,
                                mass: Mass(kilograms: 80),
                                reps: 8,
                                rpe: 8
                            ),
                            SetEntryDraft(
                                setIndex: 1,
                                status: .planned,
                                mass: Mass(kilograms: 80),
                                reps: 8
                            )
                        ]
                    )
                ]
            ),
            recoveryState: .active
        )

        let block = InSessionCoachContextBuilder.sessionExerciseBlock(
            snapshot: snapshot,
            displayNames: ["bench_press": "Bench Press"]
        )

        #expect(block.contains("80 kg"))
        #expect(block.contains("x 8"))
        #expect(block.contains("RPE 8"))
        #expect(block.contains("completed"))
    }

    @Test("import context notes appear in exercise block")
    func importNotesParity() {
        let snapshot = ActiveSessionSnapshot(
            session: WorkoutSessionDraft(
                notes: "Bodyweight Baseline: ~72.5 kg\nWarm-up: shoulder rotations",
                startedAt: Date(),
                status: .active,
                source: .importSource,
                exercises: []
            ),
            recoveryState: .active
        )

        let block = InSessionCoachContextBuilder.sessionExerciseBlock(
            snapshot: snapshot,
            displayNames: [:],
            importContextNotes: InSessionCoachContextBuilder.importContextNotes(from: snapshot.session.notes)
        )

        #expect(block.contains("Bodyweight Baseline"))
        #expect(block.contains("Warm-up"))
    }
}
