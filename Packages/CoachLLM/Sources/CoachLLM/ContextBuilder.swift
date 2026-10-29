import Core
import Foundation

/// Pure assembler for coach prompts with stable-prefix ordering and token trimming.
public enum ContextBuilder {
    public static func build(
        profile: MemoryProfile,
        days: CoachContextDays,
        budget: Int,
        turn: ContextTurn,
        appSurface: CoachAppSurfaceSnapshot? = nil,
        calendarDay: HelmDay? = nil
    ) -> CoachPrompt {
        var systemInstructions = CoachSystemPrompt.chatV1
        if let style = profile.globalStyle ?? profile.trainingStyle {
            systemInstructions += "\n\n" + style.promptDelta
        }
        let stablePrefix = stablePrefixText(profile: profile, days: days)

        let sortedDays = days.recent.sorted { $0.helmDay < $1.helmDay }
        let referenceDay = coachReferenceDay(calendarDay: calendarDay, days: days)
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
                budget: budget,
                referenceDay: referenceDay
            )
        }
        let contextBlock: String
        switch turn {
        case .followUp:
            contextBlock = trimFollowUpBlockToBudget(
                sections: followUpSections(
                    from: days,
                    profile: profile,
                    calendarDay: calendarDay,
                    referenceDay: referenceDay
                ),
                systemInstructions: systemInstructions,
                budget: budget
            )
        case .initial:
            contextBlock = assembleContextBlock(
                stablePrefix: stablePrefix,
                days: includedDays,
                referenceDay: referenceDay
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

        let patterns = normalized(days.patternFindings)
        if !patterns.isEmpty {
            sections.append("# Pattern Findings\n\(patterns)")
        }

        let evidence = {
            let grouped = EvidenceIndex.groupedText(from: days.groupedEvidence)
            if !grouped.isEmpty { return grouped }
            return EvidenceIndex.stableText(from: days.evidence)
        }()
        if !evidence.isEmpty {
            sections.append("# Evidence Index\n\(evidence)")
        }

        if let training = recentTrainingSection(
            workouts: normalized(days.recentWorkouts),
            outcomes: days.recentSessionOutcomes
        ) {
            sections.append(training)
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

    private static func followUpSections(
        from days: CoachContextDays,
        profile: MemoryProfile,
        calendarDay: HelmDay? = nil,
        referenceDay: HelmDay
    ) -> [String] {
        var sections: [String] = [
            clockLine(for: referenceDay)
        ]
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
        let patterns = normalized(days.patternFindings)
        if !patterns.isEmpty {
            sections.append("# Pattern Findings\n\(patterns)")
        }
        appendTodaySection(
            days: days,
            calendarDay: calendarDay,
            referenceDay: referenceDay,
            into: &sections
        )
        if let training = recentTrainingSection(
            workouts: normalized(days.recentWorkouts),
            outcomes: days.recentSessionOutcomes
        ) {
            sections.append(training)
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

    private static func appendTodaySection(
        days: CoachContextDays,
        calendarDay: HelmDay?,
        referenceDay: HelmDay,
        into sections: inout [String]
    ) {
        let calendar = coachCalendar
        guard let calendarDay else {
            if let today = days.recent.max(by: { $0.helmDay < $1.helmDay }) {
                let todayText = normalized(today.text)
                if !todayText.isEmpty {
                    sections.append("# Today\n## \(labeled(today.helmDay, relativeTo: referenceDay, calendar: calendar))\n\(todayText)")
                }
            }
            return
        }

        if let match = days.recent.first(where: { $0.helmDay == calendarDay }) {
            let todayText = normalized(match.text)
            if !todayText.isEmpty {
                sections.append("# Today\n## \(labeled(match.helmDay, relativeTo: referenceDay, calendar: calendar))\n\(todayText)")
            } else {
                sections.append("# Today\n## \(labeled(calendarDay, relativeTo: referenceDay, calendar: calendar))\nno_daily_row_yet")
            }
        } else {
            sections.append("# Today\n## \(labeled(calendarDay, relativeTo: referenceDay, calendar: calendar))\nno_daily_row_yet")
        }

        if let latest = days.recent.max(by: { $0.helmDay < $1.helmDay }),
           latest.helmDay != calendarDay {
            let latestText = normalized(latest.text)
            if !latestText.isEmpty {
                sections.append("# Latest day\n## \(labeled(latest.helmDay, relativeTo: referenceDay, calendar: calendar))\n\(latestText)")
            }
        }
    }

    private static var coachCalendar: Calendar { Calendar(identifier: .gregorian) }

    private static func coachReferenceDay(calendarDay: HelmDay?, days: CoachContextDays) -> HelmDay {
        if let calendarDay { return calendarDay }
        if let newest = days.recent.map(\.helmDay).max() { return newest }
        return HelmDay.day(for: Date(), calendar: coachCalendar)
    }

    private static func clockLine(for day: HelmDay) -> String {
        "now=\(day.coachClockLabel(calendar: coachCalendar))"
    }

    private static func labeled(_ day: HelmDay, relativeTo today: HelmDay, calendar: Calendar) -> String {
        day.coachContextLabel(relativeTo: today, calendar: calendar)
    }

    private static func assembleContextBlock(
        stablePrefix: String,
        days: [CoachContextDay],
        referenceDay: HelmDay
    ) -> String {
        let clock = clockLine(for: referenceDay)
        guard !days.isEmpty else { return [clock, stablePrefix].joined(separator: "\n\n") }

        let daySections = days.map { day in
            "## \(labeled(day.helmDay, relativeTo: referenceDay, calendar: coachCalendar))\n\(normalized(day.text))"
        }
        return ([clock, stablePrefix, "# Recent Days"] + daySections).joined(separator: "\n\n")
    }

    private static func trimDaysToBudget(
        stablePrefix: String,
        days: [CoachContextDay],
        budget: Int,
        referenceDay: HelmDay
    ) -> (included: [CoachContextDay], dropped: Int) {
        guard budget > 0 else {
            return ([], days.count)
        }

        var remaining = days
        while !remaining.isEmpty {
            let candidate = assembleContextBlock(
                stablePrefix: stablePrefix,
                days: remaining,
                referenceDay: referenceDay
            )
            if TokenBudget.estimateTokens(characterCount: candidate.count) <= budget {
                return (remaining, days.count - remaining.count)
            }
            remaining.removeFirst()
        }

        return ([], days.count)
    }

    private static func recentTrainingSection(
        workouts: String,
        outcomes: [SessionOutcomeCard]
    ) -> String? {
        guard !workouts.isEmpty || !outcomes.isEmpty else { return nil }
        if outcomes.isEmpty {
            return "# Recent Workouts\n\(workouts)"
        }
        var lines = ["# Recent Sessions\n\(outcomes.map(\.llmText).joined(separator: "\n"))"]
        if !workouts.isEmpty {
            lines.append("# Recent Workouts\n\(workouts)")
        }
        return lines.joined(separator: "\n\n")
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
