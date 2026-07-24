import Foundation

public extension MuscleVolumeBoardModel {
    static let stateCoverageFixture = MuscleVolumeBoardModel(rows: [
        MuscleVolumeBoardRow(
            id: "quads",
            label: "Quads",
            weeklySets: 4,
            mev: 8,
            mrv: 18,
            state: .depleted,
            daysSinceTrained: 5
        ),
        MuscleVolumeBoardRow(
            id: "chest",
            label: "Chest",
            weeklySets: 14,
            mev: 10,
            mrv: 20,
            state: .ready,
            daysSinceTrained: 2
        ),
        MuscleVolumeBoardRow(
            id: "back",
            label: "Back",
            weeklySets: 18,
            mev: 10,
            mrv: 18,
            state: .primed,
            daysSinceTrained: 0
        ),
        MuscleVolumeBoardRow(
            id: "hamstrings",
            label: "Hamstrings",
            weeklySets: 22,
            mev: 8,
            mrv: 16,
            state: .compromised,
            daysSinceTrained: 1
        ),
        MuscleVolumeBoardRow(
            id: "shoulders",
            label: "Shoulders",
            weeklySets: 0,
            mev: 8,
            mrv: 20,
            state: .depleted,
            daysSinceTrained: nil
        )
    ])

    static let emptyFixture = MuscleVolumeBoardModel(rows: [])
}
