import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Workout export formatter")
struct WorkoutExportFormatterTests {
    @Test("prescription export body parses through WorkoutTextParser")
    func prescriptionExportParses() {
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 29),
            title: "Push Day",
            exercises: [
                PrescribedExercise(
                    exerciseID: "seed-bench-press",
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 8,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                ),
                PrescribedExercise(
                    exerciseID: "seed-pull-up",
                    order: 1,
                    targetSets: 2,
                    targetRepMin: 10,
                    targetRepMax: 10
                )
            ]
        )
        let names = [
            "seed-bench-press": "Bench Press (Barbell)",
            "seed-pull-up": "Pull Up"
        ]
        let body = WorkoutExportFormatter.formatPrescriptionBody(
            prescription: prescription,
            displayNames: names
        )
        let parsed = WorkoutTextParser.parse(body)

        #expect(parsed.title == "Push Day")
        #expect(parsed.exercises.count == 2)
        #expect(parsed.exercises[0].exerciseTitle == "Bench Press (Barbell)")
        #expect(parsed.exercises[0].sets.count == 3)
        #expect(parsed.exercises[0].sets[0].mass?.kilograms == 80)
        #expect(parsed.exercises[0].sets[0].reps == 8)
        #expect(parsed.exercises[0].sets[0].rpe == 8)
        #expect(parsed.exercises[1].exerciseTitle == "Pull Up")
        #expect(parsed.exercises[1].sets.count == 2)
        #expect(parsed.exercises[1].sets[0].setType == .bodyweight)
        #expect(parsed.exercises[1].sets[0].reps == 10)
    }

    @Test("prescription clipboard export keeps verification header")
    func prescriptionClipboardIncludesHeader() {
        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 29),
            title: "Leg Day",
            exercises: [
                PrescribedExercise(
                    exerciseID: "seed-squat",
                    order: 0,
                    targetSets: 1,
                    targetRepMin: 5,
                    targetRepMax: 5,
                    targetMass: Mass(kilograms: 100)
                )
            ]
        )
        let text = WorkoutExportFormatter.formatPrescriptionForClipboard(
            prescription: prescription,
            displayNames: ["seed-squat": "Squat (Barbell)"]
        )
        #expect(text.contains("Helm prescription export"))
        #expect(text.contains("Leg Day"))
        #expect(text.contains("Set 1: 100 kg x 5"))
    }
}
