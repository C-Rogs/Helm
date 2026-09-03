import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence
import PlanKit

enum CoachContextBootstrap {
    static func assemble(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = CoachContextAssembler.defaultLookbackDays
    ) async throws -> CoachContextDays {
        let weekStart = endDay.mondayOfSameWeek()
        let weekEnd = endDay.adding(days: WeekAheadScheduleBuilder.horizonDays - 1)
        let loads = await CalendarHintBootstrap.service.dayLoads(from: weekStart, through: weekEnd)
        let classifications = await CalendarHintBootstrap.eventClassifier.classify(loads: loads)
        let prescriptionSummary = await MainActor.run {
            PlanBootstrap.prescriptionService.state.summary
        }

        let fullyBlocked = CalendarEventClassifier.fullyBlockedDays(from: [:], classifications: classifications)
        let partiallyBlocked = CalendarEventClassifier.partiallyBlockedDays(from: classifications)
        let busyDayHints = Self.buildCoachBusyHints(
            loads: loads,
            classifications: classifications,
            fullyBlocked: fullyBlocked,
            partiallyBlocked: partiallyBlocked
        )
        let todayPrescription = Self.todayPrescriptionText(from: prescriptionSummary)

        return try await Task.detached(priority: .userInitiated) {
            try await assemblePersistedContext(
                from: store,
                endingAt: endDay,
                lookbackDays: lookbackDays,
                busyDayHints: busyDayHints,
                todayPrescription: todayPrescription,
                prescriptionSummary: prescriptionSummary
            )
        }.value
    }

    private static func assemblePersistedContext(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int,
        busyDayHints: [HelmDay: String],
        todayPrescription: String,
        prescriptionSummary: PrescribedSessionSummary?
    ) async throws -> CoachContextDays {
        let prescriptionLoadSummary = try Self.prescriptionLoadSummaryText(
            from: store,
            endingAt: endDay,
            summary: prescriptionSummary
        )
        let volumeStateSummary = try Self.volumeStateText(from: store, endingAt: endDay)
        let engineProfile = try Self.engineProfileText(from: store, endingAt: endDay)

        let profile = try store.memoryProfile.load()
        let (evidence, groupedEvidence, moduleSummaries) = Self.resolveModuleEvidence(profile: profile)

        let freshness = CoachContextFreshness(blocks: [
            .init(key: .nutritionDiary, fetchedAt: .now),
            .init(key: .todayPrescription, fetchedAt: .now),
            .init(key: .recentWorkouts, fetchedAt: .now),
            .init(key: .readinessBaselines, fetchedAt: .now),
            .init(key: .weekAheadSchedule, fetchedAt: .now),
            .init(key: .evidenceIndex, fetchedAt: .now),
            .init(key: .trainingPlanSnapshot, fetchedAt: .now)
        ])

        let outcomes = try Self.sessionOutcomeCards(from: store)

        return try await CoachContextAssembler.assemble(
            from: store,
            endingAt: endDay,
            lookbackDays: lookbackDays,
            evidence: evidence,
            groupedEvidence: groupedEvidence,
            busyDayHints: busyDayHints,
            todayPrescription: todayPrescription,
            prescriptionLoadSummary: prescriptionLoadSummary,
            volumeStateSummary: volumeStateSummary,
            engineProfile: engineProfile,
            moduleSummaries: moduleSummaries,
            recentSessionOutcomes: outcomes,
            freshness: freshness
        )
    }

    private static func sessionOutcomeCards(from store: PersistenceStore) throws -> [SessionOutcomeCard] {
        let recentSummaries = try store.workoutSessions.listSummaries(limit: 7)
        let sessionsByID = try store.workoutSessions.fetch(ids: recentSummaries.map(\.id))
        let exerciseIDs = Array(
            Set(sessionsByID.values.flatMap { $0.exercises.map(\.exerciseID) })
        )
        let displayNames = (try? store.exercises.displayNames(for: exerciseIDs)) ?? [:]

        return recentSummaries.map { summary in
            let day = HelmDay.day(for: summary.startedAt, cutoff: .default, calendar: .current)
            var exercises: [SessionOutcomeCard.ExerciseOutcome] = []
            var prescribedBy: SessionOutcomeCard.PrescriptionSource = .engine
            var attributedMessageID: String?

            if let session = sessionsByID[summary.id] {
                let prescribed: [PrescribedExercise] = PrescriptionDayStore.load(for: day)?.exercises ?? []
                let prescribedByID: [String: PrescribedExercise] = Dictionary(
                    uniqueKeysWithValues: prescribed.map { ($0.exerciseID, $0) }
                )

                exercises = session.exercises.map { exercise in
                    let name = displayNames[exercise.exerciseID] ?? exercise.exerciseID
                    let completedSets = exercise.sets.filter {
                        $0.status == .completed && !$0.setType.isWarmup
                    }.count
                    let rx = prescribedByID[exercise.exerciseID]
                    let prescribedSets = rx?.targetSets ?? completedSets

                    var deviations: [SessionOutcomeCard.ExerciseOutcome.Deviation] = []
                    if prescribedSets > 0 || rx != nil {
                        if completedSets < prescribedSets {
                            deviations.append(.volumeSkipped)
                        } else if completedSets > prescribedSets {
                            deviations.append(.volumeExtra)
                        } else {
                            deviations.append(.matched)
                        }
                    } else {
                        deviations.append(.matched)
                    }

                    return SessionOutcomeCard.ExerciseOutcome(
                        name: name,
                        prescribedSets: prescribedSets,
                        completedSets: completedSets,
                        deviations: deviations
                    )
                }

                let adviceRecords = (try? store.coachAdviceRecords.fetch(
                    helmDay: day.formatted,
                    adviceType: .workoutStart
                )) ?? []
                attributedMessageID = adviceRecords.first(where: { $0.state == .actedOn })
                    .map(\.messageID)
                    ?? adviceRecords.first?.messageID

                if adviceRecords.contains(where: { $0.state == .actedOn || $0.state == .pending }) {
                    prescribedBy = .coachCustom
                } else {
                    prescribedBy = .engine
                }
            }

            return SessionOutcomeCard(
                helmDay: day.formatted,
                sessionType: summary.title ?? "Workout",
                durationMinutes: summary.endedAt.map {
                    Int($0.timeIntervalSince(summary.startedAt) / 60)
                } ?? 0,
                estimatedTRIMP: 0,
                completed: true,
                exercises: exercises,
                attributedMessageID: attributedMessageID,
                prescribedBy: prescribedBy
            )
        }
    }

    private static func resolveModuleEvidence(profile: MemoryProfile) -> (evidence: [EvidenceRecord], groupedEvidence: [String: [EvidenceRecord]], moduleSummaries: String) {
        guard let index = ResourceModuleIndex.shared else {
            return (MethodologyEvidenceSupport.allRecords, [:], "")
        }
        let moduleIDs: [String]
        if !profile.activeModules.isEmpty {
            moduleIDs = profile.activeModules
        } else {
            moduleIDs = index.defaultModuleIDs(for: profile.phaseGoal)
        }
        let evidence = index.filteredEvidence(moduleIDs: moduleIDs)

        var grouped: [String: [EvidenceRecord]] = [:]
        for ev in evidence {
            let evModuleID = Self.moduleForEvidence(ev.id)
            let title = index.moduleTitle(for: evModuleID) ?? evModuleID
            grouped[title, default: []].append(ev)
        }

        let summaries = index.moduleSummaries(moduleIDs: moduleIDs)
        return (evidence, grouped, summaries)
    }

    private static func moduleForEvidence(_ evidenceID: String) -> String {
        let parts = evidenceID.split(separator: "-")
        guard parts.count >= 3, parts[0] == "ev" else { return evidenceID }
        return parts.dropFirst().prefix(while: { !$0.contains(where: { $0.isNumber }) }).joined(separator: "-")
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

    private static func todayPrescriptionText(from summary: PrescribedSessionSummary?) -> String {
        guard let summary else { return "" }
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

    private static func prescriptionLoadSummaryText(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        summary: PrescribedSessionSummary?
    ) throws -> String {
        guard let summary, !summary.exercises.isEmpty else { return "" }

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
