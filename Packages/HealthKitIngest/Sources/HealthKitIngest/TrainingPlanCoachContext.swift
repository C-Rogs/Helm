import Core
import Foundation
import PlanKit

/// Grounded training-plan snapshot for the coach. Emphasis is verbatim athlete intent, not parsed by PlanKit.
public enum TrainingPlanCoachContext {
    public struct Input: Sendable, Equatable {
        public let emphasis: String?
        /// Nil when today is an intentional rest / non-training day in the week plan.
        public let todaySplit: SessionSplitKind?
        public let weeklyLedger: WeeklyHardSetLedger
        public let mesocycleState: MesocycleState?
        public let experience: TrainingExperience
        public let remainingSessionsThisWeek: Int
        public let pendingReactiveDeload: Bool
        public let sessionDurationMinutes: Int
        public let programTemplate: String
        public let allowedEquipment: Set<String>

        public init(
            emphasis: String?,
            todaySplit: SessionSplitKind?,
            weeklyLedger: WeeklyHardSetLedger,
            mesocycleState: MesocycleState?,
            experience: TrainingExperience,
            remainingSessionsThisWeek: Int,
            pendingReactiveDeload: Bool = false,
            sessionDurationMinutes: Int = 60,
            programTemplate: String = "ppl",
            allowedEquipment: Set<String> = []
        ) {
            self.emphasis = emphasis
            self.todaySplit = todaySplit
            self.weeklyLedger = weeklyLedger
            self.mesocycleState = mesocycleState
            self.experience = experience
            self.remainingSessionsThisWeek = max(1, remainingSessionsThisWeek)
            self.pendingReactiveDeload = pendingReactiveDeload
            self.sessionDurationMinutes = sessionDurationMinutes
            self.programTemplate = programTemplate
            self.allowedEquipment = allowedEquipment
        }
    }

    public static func build(from input: Input) -> String {
        var lines: [String] = [
            "engine_note=split_rotation_only; emphasis is athlete intent for coach interpretation",
            "today_split=\(input.todaySplit?.label ?? "Rest")",
            "remaining_sessions_this_week=\(input.remainingSessionsThisWeek)",
            "session_duration_min=\(input.sessionDurationMinutes)",
            "program_template=\(input.programTemplate)"
        ]

        if input.pendingReactiveDeload {
            lines.append("pending_reactive_deload=true (engine proposes full-week deload; needs athlete confirm)")
        }

        if let meso = input.mesocycleState {
            lines.append("consecutive_depleted_days=\(meso.consecutiveDepletedDays)")
            if !meso.muscles.isEmpty {
                lines.append("mesocycle_per_muscle:")
                for (muscle, muscleState) in meso.muscles.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    lines.append(
                        "  \(muscle.rawValue): phase=\(muscleState.phase) week=\(muscleState.currentWeek)/\(muscleState.blockLengthWeeks)"
                    )
                }
            }
        }

        if !input.allowedEquipment.isEmpty {
            lines.append("allowed_equipment=\(input.allowedEquipment.sorted().joined(separator: ","))")
        }

        if let emphasis = normalizedEmphasis(input.emphasis) {
            lines.append("emphasis=\"\(emphasis)\"")
        }

        lines.append("rolling_7d_hard_sets:")
        for muscle in MuscleGroup.allCases {
            let weeklySets = input.weeklyLedger.totals[muscle, default: 0]
            let landmarks = input.mesocycleState?.muscles[muscle]?.landmarks
                ?? PlanKit.seedLandmarks(muscle: muscle, experience: input.experience)
            let weeklyTarget = input.mesocycleState?.muscles[muscle].map {
                PlanKit.weeklyHardSetTarget(for: $0)
            }
            let targetSuffix = weeklyTarget.map { " weekly_target=\($0)" } ?? ""
            lines.append(
                "  \(muscle.rawValue): \(formatSets(weeklySets)) hard sets | MEV \(landmarks.mev) MRV \(landmarks.mrv)\(targetSuffix)"
            )
        }

        return lines.joined(separator: "\n")
    }

    public static func normalizedEmphasis(_ emphasis: String?) -> String? {
        let trimmed = emphasis?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func emphasisDisplayLabel(_ emphasis: String?) -> String? {
        guard let normalized = normalizedEmphasis(emphasis) else { return nil }
        return "Emphasis: \(normalized)"
    }

    private static func formatSets(_ value: Double) -> String {
        SessionDesignBriefBuilder.formatHardSets(value)
    }
}
