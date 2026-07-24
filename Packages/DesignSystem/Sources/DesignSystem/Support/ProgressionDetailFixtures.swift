import Foundation

public extension ProgressionDetailModel {
    static let midMesoFixture = ProgressionDetailModel(
        phaseLabel: "Gain · v-taper",
        experienceLabel: "Intermediate",
        blockSummary: "Week 3 of 5 · Accumulating",
        isDeloadWeek: false,
        muscles: [
            MesocycleMuscleRow(
                id: "chest", label: "Chest", currentWeek: 3, blockLengthWeeks: 5,
                phaseLabel: "Accumulating", weeklyTarget: 14, weeklyDone: 10,
                mev: 8, mrv: 18, state: .ready
            ),
            MesocycleMuscleRow(
                id: "back", label: "Back", currentWeek: 3, blockLengthWeeks: 5,
                phaseLabel: "Accumulating", weeklyTarget: 16, weeklyDone: 12,
                mev: 8, mrv: 20, state: .ready
            ),
            MesocycleMuscleRow(
                id: "quads", label: "Quads", currentWeek: 3, blockLengthWeeks: 5,
                phaseLabel: "Accumulating", weeklyTarget: 15, weeklyDone: 6,
                mev: 8, mrv: 20, state: .depleted
            )
        ],
        scheme: ProgressionSchemeSummary(
            repRange: "8-12", rpeCap: "RPE 8.5", targetRPE: "RPE 8.0",
            loadIncrement: "+2.5%", setsPerSession: "3-4 / exercise"
        ),
        ladders: [
            LiftLadderRow(
                id: "bench_press", displayName: "Bench Press (Barbell)",
                currentE1RMKilograms: 102.5, workingWeightKilograms: 82.0,
                targetRepRange: "8-12",
                steps: [
                    LiftLadderStep(id: "bench-1", stepIndex: 1, title: "95 kg e1RM",
                        e1RMKilograms: 95.0, deltaKilograms: nil, isCompleted: true, achievedAtLabel: "Jun 12"),
                    LiftLadderStep(id: "bench-2", stepIndex: 2, title: "98 kg e1RM",
                        e1RMKilograms: 98.0, deltaKilograms: 3.0, isCompleted: true, achievedAtLabel: "Jul 3"),
                    LiftLadderStep(id: "bench-3", stepIndex: 3, title: "102 kg e1RM",
                        e1RMKilograms: 102.5, deltaKilograms: 4.5, isCompleted: true, achievedAtLabel: "Jul 18"),
                    LiftLadderStep(id: "bench-4", stepIndex: 4, title: "Next: 82 kg × 8-12",
                        e1RMKilograms: nil, deltaKilograms: nil, isCompleted: false, achievedAtLabel: nil)
                ]
            ),
            LiftLadderRow(
                id: "squat", displayName: "Squat (Barbell)",
                currentE1RMKilograms: 140.0, workingWeightKilograms: 112.5,
                targetRepRange: "8-12",
                steps: [
                    LiftLadderStep(id: "squat-1", stepIndex: 1, title: "128 kg e1RM",
                        e1RMKilograms: 128.0, deltaKilograms: nil, isCompleted: true, achievedAtLabel: "Jun 5"),
                    LiftLadderStep(id: "squat-2", stepIndex: 2, title: "140 kg e1RM",
                        e1RMKilograms: 140.0, deltaKilograms: 12.0, isCompleted: true, achievedAtLabel: "Jul 10"),
                    LiftLadderStep(id: "squat-3", stepIndex: 3, title: "Next: 112.5 kg × 8-12",
                        e1RMKilograms: nil, deltaKilograms: nil, isCompleted: false, achievedAtLabel: nil)
                ]
            )
        ],
        isColdStart: false
    )

    static let deloadWeekFixture = ProgressionDetailModel(
        phaseLabel: "Maintain", experienceLabel: "Intermediate",
        blockSummary: "Week 5 of 5 · Deload", isDeloadWeek: true,
        muscles: [
            MesocycleMuscleRow(
                id: "chest", label: "Chest", currentWeek: 5, blockLengthWeeks: 5,
                phaseLabel: "Deload", weeklyTarget: 9, weeklyDone: 4,
                mev: 8, mrv: 18, state: .ready
            ),
            MesocycleMuscleRow(
                id: "back", label: "Back", currentWeek: 5, blockLengthWeeks: 5,
                phaseLabel: "Deload", weeklyTarget: 10, weeklyDone: 6,
                mev: 8, mrv: 20, state: .ready
            )
        ],
        scheme: ProgressionSchemeSummary(
            repRange: "8-12", rpeCap: "RPE 7.0", targetRPE: "RPE 6.5",
            loadIncrement: "+2.5%", setsPerSession: "2-3 / exercise"
        ),
        ladders: [
            LiftLadderRow(
                id: "bench_press", displayName: "Bench Press (Barbell)",
                currentE1RMKilograms: 102.5, workingWeightKilograms: 80.0,
                targetRepRange: "8-12",
                steps: [
                    LiftLadderStep(id: "bench-deload-1", stepIndex: 1, title: "102 kg e1RM",
                        e1RMKilograms: 102.5, deltaKilograms: nil, isCompleted: true, achievedAtLabel: "Jul 18"),
                    LiftLadderStep(id: "bench-deload-2", stepIndex: 2, title: "Deload: 80 kg × 8-12",
                        e1RMKilograms: nil, deltaKilograms: nil, isCompleted: false, achievedAtLabel: nil)
                ]
            )
        ],
        isColdStart: false
    )

    static let coldStartFixture = ProgressionDetailModel(
        phaseLabel: "Gain", experienceLabel: "Novice",
        blockSummary: "Week 1 of 5 · Accumulating", isDeloadWeek: false,
        muscles: [
            MesocycleMuscleRow(
                id: "chest", label: "Chest", currentWeek: 1, blockLengthWeeks: 5,
                phaseLabel: "Accumulating", weeklyTarget: 7, weeklyDone: 0,
                mev: 7, mrv: 15, state: .depleted
            ),
            MesocycleMuscleRow(
                id: "back", label: "Back", currentWeek: 1, blockLengthWeeks: 5,
                phaseLabel: "Accumulating", weeklyTarget: 7, weeklyDone: 0,
                mev: 7, mrv: 17, state: .depleted
            )
        ],
        scheme: ProgressionSchemeSummary(
            repRange: "8-12", rpeCap: "RPE 8.5", targetRPE: "RPE 8.0",
            loadIncrement: "+2.5%", setsPerSession: "3 / exercise"
        ),
        ladders: [],
        isColdStart: true
    )
}
