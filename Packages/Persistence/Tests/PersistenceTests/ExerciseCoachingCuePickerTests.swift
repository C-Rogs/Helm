import Foundation
import Testing
@testable import Persistence

@Suite("Exercise coaching cue picker")
struct ExerciseCoachingCuePickerTests {
    @Test("seed cues take priority over instruction text")
    func prefersSeedCues() {
        let seedCues = ["Brace hard.", "Drive the floor away.", "Chest proud."]
        let cue = ExerciseCoachingCuePicker.cue(
            coachingCues: seedCues,
            instructionText: "This instruction sentence is definitely long enough to parse.",
            exerciseID: "seed-squat",
            sessionID: "session-a"
        )
        #expect(cue.map { seedCues.contains($0) } == true)
    }

    @Test("instruction text is used when seed cues are empty")
    func fallsBackToInstructionText() {
        let cue = ExerciseCoachingCuePicker.cue(
            coachingCues: [],
            instructionText: "Keep elbows tucked close to your sides throughout every repetition.",
            exerciseID: "seed-bench-press",
            sessionID: "session-a"
        )
        #expect(cue == "Keep elbows tucked close to your sides throughout every repetition.")
    }

    @Test("session hash rotates among seed cue variants")
    func rotatesBySessionID() {
        let cues = ["Cue one is long enough.", "Cue two is long enough.", "Cue three is long enough."]
        let first = ExerciseCoachingCuePicker.cue(
            coachingCues: cues,
            instructionText: nil,
            exerciseID: "seed-bench-press",
            sessionID: "session-a"
        )
        let second = ExerciseCoachingCuePicker.cue(
            coachingCues: cues,
            instructionText: nil,
            exerciseID: "seed-bench-press",
            sessionID: "session-b"
        )
        let third = ExerciseCoachingCuePicker.cue(
            coachingCues: cues,
            instructionText: nil,
            exerciseID: "seed-bench-press",
            sessionID: "session-c"
        )
        let picked = [first, second, third].compactMap { $0 }
        #expect(picked.allSatisfy { cues.contains($0) })
        #expect(Set(picked).count >= 2)
    }
}
