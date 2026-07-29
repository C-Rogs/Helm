import Core
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Emphasis volume policy")
struct EmphasisVolumePolicyTests {
    @Test("arm emphasis adds biceps and triceps without replacing split muscles")
    func armEmphasisAddsSlots() {
        let base: [MuscleGroup] = [.chest, .shoulders, .triceps]
        let augmented = EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: "Arms")
        #expect(augmented.contains(.biceps))
        #expect(augmented.contains(.triceps))
        #expect(augmented.contains(.chest))
    }

    @Test("session brief surfaces arm emphasis as weekly progress copy")
    func briefUsesWeeklyProgressCopy() {
        let mesocycle = PlanKit.makeInitialState(muscles: [.biceps, .triceps], experience: .intermediate)
        let ledger = WeeklyHardSetLedger(
            weekStart: HelmDay(year: 2026, month: 7, day: 27),
            totals: [.biceps: 2, .triceps: 1]
        )
        let brief = SessionDesignBriefBuilder.build(
            splitKind: .push,
            targetMuscles: [.chest, .shoulders, .triceps, .biceps],
            phaseGoal: PhaseGoal(phase: .maintain, emphasis: "Arms"),
            mesocycleState: mesocycle,
            totalSets: 18,
            exerciseCount: 5,
            readiness: nil,
            weeklyLedger: ledger
        )

        #expect(brief.emphasisProgressLabel?.hasPrefix("Arm emphasis ·") == true)
        #expect(brief.summary.contains("Arm emphasis ·") == true)
        #expect(!brief.summary.contains("Arms"))
    }

    @Test("empty emphasis leaves targets unchanged")
    func noEmphasis() {
        let base: [MuscleGroup] = [.back, .biceps]
        #expect(
            EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: nil) == base
        )
    }
}
