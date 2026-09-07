import Foundation

public extension ExerciseHistoryModel {
    static let benchFixture = ExerciseHistoryModel(
        exerciseName: "Bench Press (Barbell)",
        instructionText: "Lie on a flat bench, plant feet, and press the bar from mid-chest to lockout.",
        coachingCues: [
            "Brace hard and pull shoulder blades together.",
            "Drive through your heels and keep your chest proud.",
            "Press up and slightly back."
        ],
        imageURL: URL(string: "https://example.com/bench.gif"),
        currentE1RMKilograms: 102.5,
        previousSets: [
            ExercisePreviousSetRow(
                id: "prev-1",
                setNumber: 1,
                setTypeLabel: "W",
                previousLabel: "60×10",
                sessionLabel: "Jul 18"
            ),
            ExercisePreviousSetRow(
                id: "prev-2",
                setNumber: 2,
                setTypeLabel: "1",
                previousLabel: "80×8",
                sessionLabel: "Jul 18"
            ),
            ExercisePreviousSetRow(
                id: "prev-3",
                setNumber: 3,
                setTypeLabel: "1",
                previousLabel: "80×8",
                sessionLabel: "Jul 18"
            )
        ],
        e1RMHistory: [
            ExerciseE1RMHistoryRow(id: "e1-1", sessionLabel: "Jul 18", e1RMKilograms: 102.5),
            ExerciseE1RMHistoryRow(id: "e1-2", sessionLabel: "Jul 3", e1RMKilograms: 98.0),
            ExerciseE1RMHistoryRow(id: "e1-3", sessionLabel: "Jun 12", e1RMKilograms: 95.0)
        ]
    )

    static let coldStartFixture = ExerciseHistoryModel(
        exerciseName: "Lat Pulldown (Cable)",
        instructionText: nil,
        coachingCues: [],
        imageURL: nil,
        currentE1RMKilograms: nil,
        previousSets: [
            ExercisePreviousSetRow(
                id: "prev-1",
                setNumber: 1,
                setTypeLabel: "1",
                previousLabel: nil,
                sessionLabel: nil
            )
        ],
        e1RMHistory: []
    )
}
