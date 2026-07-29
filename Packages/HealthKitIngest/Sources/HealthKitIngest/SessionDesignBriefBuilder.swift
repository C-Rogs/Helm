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
    public let emphasisProgressLabel: String?

    public init(
        title: String,
        summary: String,
        rationale: [String],
        splitKind: SessionSplitKind,
        scheduleNotes: [String] = [],
        emphasisProgressLabel: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.splitKind = splitKind
        self.scheduleNotes = scheduleNotes
        self.emphasisProgressLabel = emphasisProgressLabel
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
        weeklyLedger: WeeklyHardSetLedger? = nil
    ) -> SessionDesignBrief {
        let title = splitKind.label
        let muscleText = SessionSplitPlanner.muscleSummary(for: targetMuscles)
        let mesoText = mesocycleSummary(for: targetMuscles, state: mesocycleState)
        var summaryParts = [muscleText, "\(totalSets) sets", mesoText]
        if let progress = weeklyLedger.flatMap({
            PlanKit.EmphasisVolumePolicy.weeklyProgress(
                emphasis: phaseGoal.emphasis,
                ledger: $0,
                mesocycleState: mesocycleState
            )
        }) {
            summaryParts.append(progress.displayText)
        }
        let summary = summaryParts.joined(separator: " · ")

        var rationale: [String] = []
        if let readiness {
            let band = readiness.band
            rationale.append("ARC \(readiness.score) (\(band.rawValue)) sets today's volume and RPE cap.")
            if band == .depleted {
                rationale.append("Volume trimmed for readiness.")
            }
        }
        rationale.append("\(phaseGoal.phase.rawValue.capitalized) phase with \(exerciseCount) exercises prescribed.")
        if let weeklyLedger {
            let progress = PlanKit.EmphasisVolumePolicy.weeklyProgress(
                emphasis: phaseGoal.emphasis,
                ledger: weeklyLedger,
                mesocycleState: mesocycleState
            )
            if let progress, !progress.hasMetFloor {
                rationale.insert(
                    "\(progress.label): \(progress.doneSets)/\(progress.targetSets) hard sets logged this week.",
                    at: min(rationale.count, 2)
                )
            }
            let progressNotes = weeklyProgressNotes(
                muscles: targetMuscles,
                ledger: weeklyLedger,
                mesocycleState: mesocycleState
            )
            rationale.append(contentsOf: progressNotes)
        }
        rationale.append(contentsOf: scheduleNotes)
        if rationale.count > 4 {
            rationale = Array(rationale.prefix(4))
        }

        let emphasisProgressLabel = weeklyLedger.flatMap {
            PlanKit.EmphasisVolumePolicy.weeklyProgress(
                emphasis: phaseGoal.emphasis,
                ledger: $0,
                mesocycleState: mesocycleState
            )
        }?.displayText

        return SessionDesignBrief(
            title: title,
            summary: summary,
            rationale: rationale,
            splitKind: splitKind,
            scheduleNotes: scheduleNotes,
            emphasisProgressLabel: emphasisProgressLabel
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
            return "\(muscle.rawValue.capitalized): \(done)/\(target) hard sets this week."
        }
        .prefix(2)
        .map { String($0) }
    }
}
