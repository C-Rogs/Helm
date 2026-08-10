import Core
import Foundation
import PlanKit
import ReadinessKit

public struct SessionDesignBrief: Sendable, Equatable {
    public let title: String
    public let summary: String
    public let rationale: [String]
    public let splitKind: SessionSplitKind
    public let scheduleNotes: [String]

    public init(
        title: String,
        summary: String,
        rationale: [String],
        splitKind: SessionSplitKind,
        scheduleNotes: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.splitKind = splitKind
        self.scheduleNotes = scheduleNotes
    }

    public var coachPromptSeed: String {
        let bullets = rationale.map { "• \($0)" }.joined(separator: "\n")
        return "Today's session is \(title): \(summary).\n\(bullets)"
    }
}

public enum SessionDesignBriefBuilder {
    public static func build(
        splitKind: SessionSplitKind,
        targetMuscles: [MuscleGroup],
        phaseGoal: PhaseGoal,
        mesocycleState: MesocycleState,
        totalSets: Int,
        exerciseCount: Int,
        readiness: ReadinessScore?,
        scheduleNotes: [String] = [],
        weeklyLedger: WeeklyHardSetLedger? = nil,
        constraintNotes: [String] = []
    ) -> SessionDesignBrief {
        _ = (exerciseCount, readiness)
        let title = splitKind.label
        let muscleText = SessionSplitPlanner.muscleSummary(for: targetMuscles)
        let mesoText = mesocycleSummary(for: targetMuscles, state: mesocycleState)
        var summaryParts = [muscleText, "\(totalSets) sets", mesoText]
        if let emphasisLabel = TrainingPlanCoachContext.emphasisDisplayLabel(phaseGoal.emphasis) {
            summaryParts.append(emphasisLabel)
        }
        let summary = summaryParts.joined(separator: " · ")

        // Keep rationale to actionable notes only. Phase and readiness score
        // already surface elsewhere on Dashboard / Train.
        var rationale: [String] = []
        rationale.append(contentsOf: constraintNotes)
        if let weeklyLedger {
            let progressNotes = weeklyProgressNotes(
                muscles: targetMuscles,
                ledger: weeklyLedger,
                mesocycleState: mesocycleState
            )
            rationale.append(contentsOf: progressNotes)
        }
        rationale.append(contentsOf: scheduleNotes)
        if rationale.count > 3 {
            rationale = Array(rationale.prefix(3))
        }

        return SessionDesignBrief(
            title: title,
            summary: summary,
            rationale: rationale,
            splitKind: splitKind,
            scheduleNotes: scheduleNotes
        )
    }

    private static func mesocycleSummary(for muscles: [MuscleGroup], state: MesocycleState) -> String {
        guard let representative = muscles.compactMap({ state.muscles[$0] }).first else {
            return "week 1 accumulating"
        }
        let phase = representative.phase == .deload ? "deload" : "accumulating"
        return "week \(representative.currentWeek) \(phase)"
    }

    private static func weeklyProgressNotes(
        muscles: [MuscleGroup],
        ledger: WeeklyHardSetLedger,
        mesocycleState: MesocycleState
    ) -> [String] {
        muscles.compactMap { muscle in
            guard let muscleState = mesocycleState.muscles[muscle] else { return nil }
            let target = PlanKit.weeklyHardSetTarget(for: muscleState)
            let done = ledger.totals[muscle, default: 0]
            return "\(muscle.rawValue.capitalized): \(formatHardSets(done))/\(target) hard sets this week."
        }
        .prefix(2)
        .map { String($0) }
    }

    /// Quantize to one decimal so float noise (e.g. 11.9999999999999) never reaches UI copy.
    static func formatHardSets(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths == tenths.rounded() {
            return String(Int(tenths.rounded()))
        }
        return String(format: "%.1f", tenths)
    }
}
