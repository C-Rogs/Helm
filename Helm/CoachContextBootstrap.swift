import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence
import PlanKit

enum CoachContextBootstrap {
    @MainActor
    static func assemble(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = CoachContextAssembler.defaultLookbackDays
    ) async throws -> CoachContextDays {
        let weekEnd = endDay.adding(days: WeekAheadScheduleBuilder.horizonDays - 1)
        let loads = await CalendarHintBootstrap.service.dayLoads(from: endDay, through: weekEnd)
        let classifications = await CalendarHintBootstrap.eventClassifier.classify(loads: loads)
        let fullyBlocked = CalendarEventClassifier.fullyBlockedDays(from: [:], classifications: classifications)
        let partiallyBlocked = CalendarEventClassifier.partiallyBlockedDays(from: classifications)

        let busyDayHints = Self.buildCoachBusyHints(
            loads: loads,
            classifications: classifications,
            fullyBlocked: fullyBlocked,
            partiallyBlocked: partiallyBlocked
        )

        let todayPrescription = Self.todayPrescriptionText()
        let prescriptionLoadSummary = try Self.prescriptionLoadSummaryText(from: store, endingAt: endDay)
        let volumeStateSummary = try Self.volumeStateText(from: store, endingAt: endDay)
        let engineProfile = try Self.engineProfileText(from: store, endingAt: endDay)

        let profile = try store.memoryProfile.load()
        let (evidence, moduleSummaries) = Self.resolveModuleEvidence(profile: profile)

        return try await CoachContextAssembler.assemble(
            from: store,
            endingAt: endDay,
            lookbackDays: lookbackDays,
            evidence: evidence,
            busyDayHints: busyDayHints,
            todayPrescription: todayPrescription,
            prescriptionLoadSummary: prescriptionLoadSummary,
            volumeStateSummary: volumeStateSummary,
            engineProfile: engineProfile,
            moduleSummaries: moduleSummaries
        )
    }

    private static func resolveModuleEvidence(profile: MemoryProfile) -> (evidence: [EvidenceRecord], moduleSummaries: String) {
        guard let index = ResourceModuleIndex.shared else {
            return (MethodologyEvidenceSupport.allRecords, "")
        }
        let moduleIDs: [String]
        if !profile.activeModules.isEmpty {
            moduleIDs = profile.activeModules
        } else {
            moduleIDs = index.defaultModuleIDs(for: profile.phaseGoal)
        }
        let evidence = index.filteredEvidence(moduleIDs: moduleIDs)
        let summaries = index.moduleSummaries(moduleIDs: moduleIDs)
        return (evidence, summaries)
    }

    private static func buildCoachBusyHints(
        loads: [HelmDay: CalendarDayLoad],
        classifications: [HelmDay: EventBlockingClassification],
        fullyBlocked: Set<HelmDay>,
        partiallyBlocked: Set<HelmDay>
    ) -> [HelmDay: String] {
        var hints: [HelmDay: String] = [:]
        for (helmDay, load) in loads {
            if fullyBlocked.contains(helmDay) {
                hints[helmDay] = "Busy (all day)"
            } else if partiallyBlocked.contains(helmDay) {
                let titles = load.allDayEventTitles.map { "\"\($0)\"" }.joined(separator: ", ")
                hints[helmDay] = "Busy (PM) - \(titles)"
            } else if let hint = BusyDayHintPolicy.hint(for: load) {
                hints[helmDay] = hint
            }
        }
        return hints
    }

    @MainActor
    private static func todayPrescriptionText() -> String {
        guard let summary = PlanBootstrap.prescriptionService.state.summary else { return "" }
        let bullets = summary.rationale.map { "  - \($0)" }.joined(separator: "\n")
        var lines = [
            "title=\(summary.title)",
            "summary=\(summary.summary)",
            "total_sets=\(summary.totalSets)",
            "readiness_adjusted=\(summary.readinessAdjusted)"
        ]
        if !bullets.isEmpty {
            lines.append("rationale:\n\(bullets)")
        }
        if !summary.exercises.isEmpty {
            lines.append("exercises:")
            for exercise in summary.exercises {
                var line = "  - \(exercise.displayName): \(exercise.targetSets) x \(exercise.targetRepRange)"
                if let load = exercise.targetLoad {
                    line += " @ \(load)"
                }
                if let rpe = exercise.targetRPE {
                    line += " (\(rpe))"
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func prescriptionLoadSummaryText(
        from store: PersistenceStore,
        endingAt endDay: HelmDay
    ) throws -> String {
        guard let summary = PlanBootstrap.prescriptionService.state.summary,
              !summary.exercises.isEmpty else { return "" }

        let history = try PrescriptionHistoryBuilder.history(from: store, endingAt: endDay)
        let profile = try store.memoryProfile.load()
        let evaluation = StandingConstraintNotes.evaluate(profile.standingConstraints, on: endDay)
        let excluded = StandingConstraintPatternPolicy.excludedPatterns(
            forActiveJoints: evaluation.activeJoints
        )

        var inputs: [PrescriptionLoadRationale.ExerciseInput] = []
        for exercise in summary.exercises {
            let progression = PlanKit.progression(
                for: exercise.id,
                history: history.loggedSets
            )
            inputs.append(
                PrescriptionLoadRationale.ExerciseInput(
                    exerciseID: exercise.id,
                    displayName: exercise.displayName,
                    progression: progression,
                    constraintAffected: PrescriptionLoadRationale.constraintAffected(
                        exerciseID: exercise.id,
                        excludedPatterns: excluded
                    )
                )
            )
        }
        return PrescriptionLoadRationale.format(exercises: inputs)
    }

    private static func volumeStateText(from store: PersistenceStore, endingAt endDay: HelmDay) throws -> String {
        let rows = try TrendsDataBuilder.buildMuscleVolumeRows(
            store: store,
            weekContaining: endDay
        )
        guard !rows.isEmpty else { return "" }
        var lines = ["per-muscle weekly volume vs MEV/MRV targets:"]
        for row in rows {
            let dayLabel = row.daysSinceTrained.map { "\($0)d ago" } ?? "untrained"
            lines.append(
                "  \(row.muscle.rawValue): \(formatSets(row.weeklySets)) sets | MEV \(row.landmarks.mev) MRV \(row.landmarks.mrv) | state=\(row.state.rawValue) | \(dayLabel)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func engineProfileText(from store: PersistenceStore, endingAt endDay: HelmDay) throws -> String {
        var lines: [String] = []

        // Standing constraints
        let profile = try store.memoryProfile.load()
        let rawConstraints = profile.standingConstraints.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawConstraints.isEmpty {
            let evaluation = StandingConstraintNotes.evaluate(rawConstraints, on: endDay)
            lines.append("standing_constraints=\"\(rawConstraints)\"")
            if !evaluation.activeJoints.isEmpty {
                lines.append("active_joints=\(evaluation.activeJoints.sorted().joined(separator: ","))")
                let excluded = StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: evaluation.activeJoints)
                if !excluded.isEmpty {
                    lines.append("excluded_patterns=\(excluded.map(\.rawValue).sorted().joined(separator: ","))")
                }
            }
            if !evaluation.rationaleNotes.isEmpty {
                lines.append("constraint_notes=\(evaluation.rationaleNotes.joined(separator: "; "))")
            }
        } else {
            lines.append("standing_constraints=none")
        }

        // Exercise selection inputs from training plan
        let settings = try store.trainingPlan.load()
        let methodology = MethodologyPreferences.parse(from: profile.preferences).preferences
        lines.append("session_duration_min=\(settings.sessionDurationMinutes)")
        lines.append("program_template=\(settings.programTemplateRaw)")
        if methodology.selectionBias != .balanced {
            lines.append("selection_bias=\(methodology.selectionBias.rawValue)")
        }
        if !methodology.allowedEquipment.isEmpty {
            lines.append("allowed_equipment=\(methodology.allowedEquipment.sorted().joined(separator: ","))")
        }

        return lines.joined(separator: "\n")
    }

    private static func formatSets(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
