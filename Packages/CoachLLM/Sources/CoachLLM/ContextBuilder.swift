import Foundation

/// Pure assembler for coach prompts with stable-prefix ordering and token trimming.
public enum ContextBuilder {
    public static func build(
        profile: MemoryProfile,
        days: CoachContextDays,
        budget: Int,
        turn: ContextTurn,
        appSurface: CoachAppSurfaceSnapshot? = nil
    ) -> CoachPrompt {
        var systemInstructions = CoachSystemPrompt.chatV1
        if let style = profile.globalStyle ?? profile.trainingStyle {
            systemInstructions += "\n\n" + style.promptDelta
        }
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
            contextBlock = trimFollowUpBlockToBudget(
                sections: followUpSections(from: days, profile: profile),
                systemInstructions: systemInstructions,
                budget: budget
            )
        case .initial:
            contextBlock = assembleContextBlock(
                stablePrefix: stablePrefix,
                days: includedDays
            )
        }

        let estimatedTokens = TokenBudget.estimateTokens(
            characterCount: systemInstructions.count + contextBlock.count
        )

        let suffix = freshnessSuffix(
            appSurface: appSurface,
            staleness: days.freshness.stalenessSummary()
        )

        return CoachPrompt(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            estimatedTokens: estimatedTokens,
            includedDayCount: includedDays.count,
            droppedDayCount: droppedDayCount,
            freshnessSuffix: suffix
        )
    }

    public static func freshnessSuffix(
        appSurface: CoachAppSurfaceSnapshot?,
        staleness: String
    ) -> String? {
        var parts: [String] = []
        if let appSurface {
            parts.append(appSurface.contextText)
        }
        if !staleness.isEmpty {
            parts.append(staleness)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    public static func stablePrefixText(profile: MemoryProfile, days: CoachContextDays) -> String {
        var sections: [String] = [
            "# Memory Profile\n\(profile.stablePrefixText())"
        ]

        let moduleSummaries = normalized(days.moduleSummaries)
        if !moduleSummaries.isEmpty {
            sections.append("# Active Resources\n\(moduleSummaries)")
        }

        let baselines = normalized(days.readinessBaselines)
        if !baselines.isEmpty {
            sections.append("# Readiness Baselines\n\(baselines)")
        }

        let evidence = {
            let grouped = EvidenceIndex.groupedText(from: days.groupedEvidence)
            if !grouped.isEmpty { return grouped }
            return EvidenceIndex.stableText(from: days.evidence)
        }()
        if !evidence.isEmpty {
            sections.append("# Evidence Index\n\(evidence)")
        }

        let workouts = normalized(days.recentWorkouts)
        let outcomes = days.recentSessionOutcomes
        if !workouts.isEmpty || !outcomes.isEmpty {
            var header = "# Recent Sessions"
            if !outcomes.isEmpty {
                let outcomesText = outcomes.map(\.llmText).joined(separator: "\n")
                var lines = ["\(header)\n\(outcomesText)"]
                if !workouts.isEmpty {
                    lines.append("# Recent Workouts\n\(workouts)")
                }
                sections.append(lines.joined(separator: "\n\n"))
            } else {
                sections.append("\(header)\n\(workouts)")
            }
        }

        let trainingPlan = normalized(days.trainingPlanSnapshot)
        if !trainingPlan.isEmpty {
            var planBlock = "# Training Plan Snapshot\n\(trainingPlan)"
            let adherenceLine = SessionOutcomeCard.weeklyAdherenceLine(from: days.recentSessionOutcomes)
            if !adherenceLine.isEmpty {
                planBlock += "\n\(adherenceLine)"
            }
            sections.append(planBlock)
        }

        let weekAhead = normalized(days.weekAheadSchedule)
        if !weekAhead.isEmpty {
            sections.append("# Week Ahead Schedule\n\(weekAhead)")
        }

        let nutritionDiary = normalized(days.nutritionDiary)
        if !nutritionDiary.isEmpty {
            sections.append("# Nutrition Diary\n\(nutritionDiary)")
        }

        let todayPrescription = normalized(days.todayPrescription)
        if !todayPrescription.isEmpty {
            sections.append("# Today's Prescription\n\(todayPrescription)")
        }

        let prescriptionLoad = normalized(days.prescriptionLoadSummary)
        if !prescriptionLoad.isEmpty {
            sections.append("# Prescription Load Rationale\n\(prescriptionLoad)")
        }

        let volumeStateSummary = normalized(days.volumeStateSummary)
        if !volumeStateSummary.isEmpty {
            sections.append("# Volume State\n\(volumeStateSummary)")
        }

        let engineProfile = normalized(days.engineProfile)
        if !engineProfile.isEmpty {
            sections.append("# Engine Profile\n\(engineProfile)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func followUpSections(from days: CoachContextDays, profile: MemoryProfile) -> [String] {
        var sections: [String] = []
        let slim = normalized(profile.slimPhaseLine())
        if !slim.isEmpty {
            sections.append("# Phase\n\(slim)")
        }
        let constraints = normalized(profile.slimStandingConstraintsText())
        if !constraints.isEmpty {
            sections.append("# Standing Constraints\n\(constraints)")
        }
        // Ambient recovery stays available every turn; deeper history uses recovery_query.v1.
        let baselines = normalized(days.readinessBaselines)
        if !baselines.isEmpty {
            sections.append("# Readiness Baselines\n\(baselines)")
        }
        if let today = days.recent.max(by: { $0.helmDay < $1.helmDay }) {
            let todayText = normalized(today.text)
            if !todayText.isEmpty {
                sections.append("# Today\n## \(today.helmDay.formatted)\n\(todayText)")
            }
        }
        let workouts = normalized(days.recentWorkouts)
        let outcomes = days.recentSessionOutcomes
        if !workouts.isEmpty || !outcomes.isEmpty {
            var header = "# Recent Sessions"
            if !outcomes.isEmpty {
                let outcomesText = outcomes.map(\.llmText).joined(separator: "\n")
                var lines = ["\(header)\n\(outcomesText)"]
                if !workouts.isEmpty {
                    lines.append("# Recent Workouts\n\(workouts)")
                }
                sections.append(lines.joined(separator: "\n\n"))
            } else {
                sections.append("\(header)\n\(workouts)")
            }
        }
        let trainingPlan = normalized(days.trainingPlanSnapshot)
        if !trainingPlan.isEmpty {
            var planBlock = "# Training Plan Snapshot\n\(trainingPlan)"
            let adherenceLine = SessionOutcomeCard.weeklyAdherenceLine(from: days.recentSessionOutcomes)
            if !adherenceLine.isEmpty {
                planBlock += "\n\(adherenceLine)"
            }
            sections.append(planBlock)
        }
        let weekAhead = normalized(days.weekAheadSchedule)
        if !weekAhead.isEmpty {
            sections.append("# Week Ahead Schedule\n\(weekAhead)")
        }
        let nutritionDiary = normalized(days.nutritionDiary)
        if !nutritionDiary.isEmpty {
            sections.append("# Nutrition Diary\n\(nutritionDiary)")
        }
        let todayPrescription = normalized(days.todayPrescription)
        if !todayPrescription.isEmpty {
            sections.append("# Today's Prescription\n\(todayPrescription)")
        }
        let prescriptionLoad = normalized(days.prescriptionLoadSummary)
        if !prescriptionLoad.isEmpty {
            sections.append("# Prescription Load Rationale\n\(prescriptionLoad)")
        }
        let volumeStateSummary = normalized(days.volumeStateSummary)
        if !volumeStateSummary.isEmpty {
            sections.append("# Volume State\n\(volumeStateSummary)")
        }
        let evidence = {
            let grouped = EvidenceIndex.groupedText(from: days.groupedEvidence)
            if !grouped.isEmpty { return grouped }
            return EvidenceIndex.stableText(from: days.evidence)
        }()
        if !evidence.isEmpty {
            sections.append("# Evidence Index\n\(evidence)")
        }
        let engineProfile = normalized(days.engineProfile)
        if !engineProfile.isEmpty {
            sections.append("# Engine Profile\n\(engineProfile)")
        }
        return sections
    }

    /// Follow-up turns previously shipped the full block with no budget check. Sections are
    /// listed lowest-priority last; drop from the end until the assembled prompt fits.
    private static func trimFollowUpBlockToBudget(
        sections: [String],
        systemInstructions: String,
        budget: Int
    ) -> String {
        guard budget > 0, !sections.isEmpty else { return sections.joined(separator: "\n\n") }

        var kept = sections
        while !kept.isEmpty {
            let candidate = kept.joined(separator: "\n\n")
            let estimated = TokenBudget.estimateTokens(
                characterCount: systemInstructions.count + candidate.count
            )
            if estimated <= budget { return candidate }
            kept.removeLast()
        }

        // Even the highest-priority section overflows; ship it alone rather than nothing.
        return sections[0]
    }

    private static func followUpContextBlock(from days: CoachContextDays, profile: MemoryProfile) -> String {
        followUpSections(from: days, profile: profile).joined(separator: "\n\n")
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
