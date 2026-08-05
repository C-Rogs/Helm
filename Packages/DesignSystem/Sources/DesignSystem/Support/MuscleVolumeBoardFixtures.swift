import Foundation

public extension MuscleVolumeBoardModel {
    static let stateCoverageFixture = MuscleVolumeBoardModel(rows: [
        MuscleVolumeBoardRow(
            id: "quads",
            label: "Quads",
            weeklySets: 4,
            scheduledSets: 6,
            mev: 8,
            mrv: 18,
            state: .depleted,
            daysSinceTrained: 5
        ),
        MuscleVolumeBoardRow(
            id: "chest",
            label: "Chest",
            weeklySets: 12,
            mev: 10,
            mrv: 20,
            state: .ready,
            daysSinceTrained: 2
        ),
        MuscleVolumeBoardRow(
            id: "back",
            label: "Back",
            weeklySets: 16,
            scheduledSets: 2,
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
            scheduledSets: 8,
            mev: 8,
            mrv: 20,
            state: .depleted,
            daysSinceTrained: nil
        )
    ])

    static let emptyFixture = MuscleVolumeBoardModel(rows: [])
}
