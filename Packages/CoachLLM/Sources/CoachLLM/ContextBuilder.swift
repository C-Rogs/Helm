import Foundation

/// Pure assembler for coach prompts with stable-prefix ordering and token trimming.
public enum ContextBuilder {
    public static func build(
        profile: MemoryProfile,
        days: CoachContextDays,
        budget: Int,
        turn: ContextTurn
    ) -> CoachPrompt {
        let systemInstructions = CoachSystemPrompt.chatV1
        let stablePrefix = stablePrefixText(profile: profile, days: days)

        let sortedDays = days.recent.sorted { $0.helmDay < $1.helmDay }
        let includedDays: [CoachContextDay]
        let droppedDayCount: Int

        switch turn {
        case .followUp:
            includedDays = []
            droppedDayCount = sortedDays.count
        case .initial:
            (includedDays, droppedDayCount) = trimDaysToBudget(
                stablePrefix: stablePrefix,
                days: sortedDays,
                budget: budget
            )
        }

        let contextBlock: String
        switch turn {
        case .followUp:
            contextBlock = followUpContextBlock(from: days)
        case .initial:
            contextBlock = assembleContextBlock(
                stablePrefix: stablePrefix,
                days: includedDays
            )
        }

        let estimatedTokens = TokenBudget.estimateTokens(
            characterCount: systemInstructions.count + contextBlock.count
        )

        return CoachPrompt(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            estimatedTokens: estimatedTokens,
            includedDayCount: includedDays.count,
            droppedDayCount: droppedDayCount
        )
    }

    public static func stablePrefixText(profile: MemoryProfile, days: CoachContextDays) -> String {
        var sections: [String] = [
            "# Memory Profile\n\(profile.stablePrefixText())"
        ]

        let baselines = normalized(days.readinessBaselines)
        if !baselines.isEmpty {
            sections.append("# Readiness Baselines\n\(baselines)")
        }

        let evidence = EvidenceIndex.stableText(from: days.evidence)
        if !evidence.isEmpty {
            sections.append("# Evidence Index\n\(evidence)")
        }

        let workouts = normalized(days.recentWorkouts)
        if !workouts.isEmpty {
            sections.append("# Recent Workouts\n\(workouts)")
        }

        let trainingPlan = normalized(days.trainingPlanSnapshot)
        if !trainingPlan.isEmpty {
            sections.append("# Training Plan Snapshot\n\(trainingPlan)")
        }

        let nutritionDiary = normalized(days.nutritionDiary)
        if !nutritionDiary.isEmpty {
            sections.append("# Nutrition Diary\n\(nutritionDiary)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func followUpContextBlock(from days: CoachContextDays) -> String {
        var sections: [String] = []
        let workouts = normalized(days.recentWorkouts)
        if !workouts.isEmpty {
            sections.append("# Recent Workouts\n\(workouts)")
        }
        let trainingPlan = normalized(days.trainingPlanSnapshot)
        if !trainingPlan.isEmpty {
            sections.append("# Training Plan Snapshot\n\(trainingPlan)")
        }
        let nutritionDiary = normalized(days.nutritionDiary)
        if !nutritionDiary.isEmpty {
            sections.append("# Nutrition Diary\n\(nutritionDiary)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func assembleContextBlock(
        stablePrefix: String,
        days: [CoachContextDay]
    ) -> String {
        guard !days.isEmpty else { return stablePrefix }

        let daySections = days.map { day in
            "## \(day.helmDay.formatted)\n\(normalized(day.text))"
        }
        return ([stablePrefix, "# Recent Days"] + daySections).joined(separator: "\n\n")
    }

    private static func trimDaysToBudget(
        stablePrefix: String,
        days: [CoachContextDay],
        budget: Int
    ) -> (included: [CoachContextDay], dropped: Int) {
        guard budget > 0 else {
            return ([], days.count)
        }

        var remaining = days
        while !remaining.isEmpty {
            let candidate = assembleContextBlock(stablePrefix: stablePrefix, days: remaining)
            if TokenBudget.estimateTokens(characterCount: candidate.count) <= budget {
                return (remaining, days.count - remaining.count)
            }
            remaining.removeFirst()
        }

        return ([], days.count)
    }

    private static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
