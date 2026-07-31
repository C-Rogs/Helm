import Core
import Foundation
import PlanKit

/// Grounded training-plan snapshot for the coach. Emphasis is verbatim athlete intent, not parsed by PlanKit.
public enum TrainingPlanCoachContext {
    public struct Input: Sendable, Equatable {
        public let emphasis: String?
        public let todaySplit: SessionSplitKind
        public let weeklyLedger: WeeklyHardSetLedger
        public let mesocycleState: MesocycleState?
        public let experience: TrainingExperience
        public let remainingSessionsThisWeek: Int

        public init(
            emphasis: String?,
            todaySplit: SessionSplitKind,
            weeklyLedger: WeeklyHardSetLedger,
            mesocycleState: MesocycleState?,
            experience: TrainingExperience,
            remainingSessionsThisWeek: Int
        ) {
            self.emphasis = emphasis
            self.todaySplit = todaySplit
            self.weeklyLedger = weeklyLedger
            self.mesocycleState = mesocycleState
            self.experience = experience
            self.remainingSessionsThisWeek = max(1, remainingSessionsThisWeek)
        }
    }

    public static func build(from input: Input) -> String {
        var lines: [String] = [
            "engine_note=split_rotation_only; emphasis is athlete intent for coach interpretation",
            "today_split=\(input.todaySplit.label)",
            "remaining_sessions_this_week=\(input.remainingSessionsThisWeek)"
        ]

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
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
