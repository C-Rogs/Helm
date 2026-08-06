import Core
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Training plan coach context")
struct TrainingPlanCoachContextTests {
    private func ledger(biceps: Double = 0, calves: Double = 0) -> WeeklyHardSetLedger {
        WeeklyHardSetLedger(
            weekStart: HelmDay(year: 2026, month: 7, day: 27),
            totals: [.biceps: biceps, .calves: calves]
        )
    }

    @Test("emphasis is passed verbatim without keyword parsing")
    func verbatimEmphasis() {
        let snapshot = TrainingPlanCoachContext.build(
            from: TrainingPlanCoachContext.Input(
                emphasis: "agility and calves",
                todaySplit: .push,
                weeklyLedger: ledger(calves: 2),
                mesocycleState: nil,
                experience: .intermediate,
                remainingSessionsThisWeek: 2
            )
        )

        #expect(snapshot.contains("emphasis=\"agility and calves\""))
        #expect(snapshot.contains("engine_note=split_rotation_only"))
        #expect(snapshot.contains("today_split=Push"))
        #expect(snapshot.contains("calves: 2 hard sets"))
        #expect(!snapshot.contains("Arm emphasis"))
    }

    @Test("rest day snapshot uses today_split=Rest")
    func restDaySplit() {
        let snapshot = TrainingPlanCoachContext.build(
            from: TrainingPlanCoachContext.Input(
                emphasis: nil,
                todaySplit: nil,
                weeklyLedger: ledger(),
                mesocycleState: nil,
                experience: .intermediate,
                remainingSessionsThisWeek: 3
            )
        )
        #expect(snapshot.contains("today_split=Rest"))
    }

    @Test("emphasis display label uses athlete wording")
    func displayLabel() {
        #expect(TrainingPlanCoachContext.emphasisDisplayLabel("calves") == "Emphasis: calves")
        #expect(TrainingPlanCoachContext.emphasisDisplayLabel("  ") == nil)
    }

    @Test("session brief surfaces verbatim emphasis not computed progress")
    func briefEmphasisCopy() {
        let mesocycle = PlanKit.makeInitialState(muscles: [.chest], experience: .intermediate)
        let brief = SessionDesignBriefBuilder.build(
            splitKind: .push,
            targetMuscles: [.chest, .shoulders, .triceps],
            phaseGoal: PhaseGoal(phase: .maintain, emphasis: "Arms"),
            mesocycleState: mesocycle,
            totalSets: 16,
            exerciseCount: 4,
            readiness: nil,
            weeklyLedger: ledger(biceps: 2)
        )

        #expect(brief.summary.contains("Emphasis: Arms"))
        #expect(!brief.summary.contains("Arm emphasis ·"))
        #expect(brief.title == "Push")
    }

    @Test("hard set copy rounds float noise and keeps true tenths")
    func formatHardSets() {
        #expect(SessionDesignBriefBuilder.formatHardSets(11.9999999999999) == "12")
        #expect(SessionDesignBriefBuilder.formatHardSets(8.0) == "8")
        #expect(SessionDesignBriefBuilder.formatHardSets(0.5) == "0.5")
        #expect(SessionDesignBriefBuilder.formatHardSets(12.0000000000001) == "12")
    }
}
