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

        #expect(block.contains("session_progress:"))
        #expect(block.contains("80 kg"))
        #expect(block.contains("x 8"))
        #expect(block.contains("RPE 8"))
        #expect(block.contains("completed"))
    }

    @Test("set lines include RIR when logged")
    func loggedRIR() {
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
                                rpe: 8,
                                rir: 2
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
        #expect(block.contains("RIR 2"))
    }

    @Test("live vitals block includes HR when present")
    func liveVitalsBlock() {
        var buffer = SessionHeartRateBuffer()
        buffer.record(bpm: 120, offsetSeconds: 10)
        buffer.record(bpm: 130, offsetSeconds: 20)
        let vitals = InSessionLiveVitals.from(
            buffer: buffer,
            currentBPM: 135,
            sessionStartedAt: Date().addingTimeInterval(-120)
        )
        let block = InSessionCoachContextBuilder.liveVitalsBlock(vitals)
        #expect(block.contains("current_hr_bpm=135"))
        #expect(block.contains("session_avg_hr_bpm=125"))
        #expect(block.contains("samples=2"))
    }

    @Test("live vitals mark HR unavailable when missing")
    func liveVitalsUnavailable() {
        let block = InSessionCoachContextBuilder.liveVitalsBlock(InSessionLiveVitals())
        #expect(block.contains("current_hr_bpm=unavailable"))
    }

    @Test("session meta includes title rest timer and recovery")
    func sessionMetaBlock() {
        let snapshot = ActiveSessionSnapshot(
            session: WorkoutSessionDraft(
                title: "Pull",
                startedAt: Date(),
                status: .active,
                source: .manual,
                exercises: []
            ),
            recoveryState: .active,
            restTimer: RestTimer(
                id: "timer-1",
                phase: .running,
                endsAt: Date().addingTimeInterval(90),
                defaultDurationSeconds: 90
            )
        )
        let block = InSessionCoachContextBuilder.sessionMetaBlock(snapshot: snapshot)
        #expect(block.contains("title=Pull"))
        #expect(block.contains("rest_timer_phase=running"))
        #expect(block.contains("recovery_state=active"))
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
