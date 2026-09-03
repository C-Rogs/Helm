import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit
import ReadinessKit

/// Maps persisted health and training rows into coach context days.
public enum CoachContextAssembler {
    public static let defaultLookbackDays = 14

    public static func assemble(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = defaultLookbackDays,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        evidence: [EvidenceRecord] = bundledMethodologyEvidence(),
        groupedEvidence: [String: [EvidenceRecord]] = [:],
        busyDayHints: [HelmDay: String] = [:],
        todayPrescription: String = "",
        prescriptionLoadSummary: String = "",
        volumeStateSummary: String = "",
        engineProfile: String = "",
        moduleSummaries: String = "",
        recentSessionOutcomes: [SessionOutcomeCard] = [],
        freshness: CoachContextFreshness = CoachContextFreshness()
    ) async throws -> CoachContextDays {
        let startDay = endDay.adding(days: -(lookbackDays - 1), calendar: calendar)
        let metrics = try store.dailyMetrics.fetchRange(from: startDay, through: endDay)
        let metricsByDay = Dictionary(uniqueKeysWithValues: metrics.map { ($0.helmDay, $0) })

        let readinessScores = try store.readiness.fetchScoreRange(from: startDay, through: endDay)
        let readinessByDay = Dictionary(uniqueKeysWithValues: readinessScores.compactMap { helmDay, json in
            decodeScoreSnippet(from: json).map { (helmDay, $0) }
        })

        let nutritionDays = Set(try store.nutrition.listDays())
        let workoutSummaries = try store.workoutSessions.listSummaries(limit: lookbackDays * 2)
        let workoutsByDay = Dictionary(
            grouping: workoutSummaries.filter { summary in
                let day = HelmDay.day(for: summary.startedAt, cutoff: cutoff, calendar: calendar)
                return day >= startDay && day <= endDay
            }
        ) { summary in
            HelmDay.day(for: summary.startedAt, cutoff: cutoff, calendar: calendar)
        }

        var days = Set(metricsByDay.keys)
        days.formUnion(readinessByDay.keys)
        days.formUnion(nutritionDays.filter { $0 >= startDay && $0 <= endDay })
        days.formUnion(workoutsByDay.keys)
        for helmDay in try store.sleep.listDays() where helmDay >= startDay && helmDay <= endDay {
            days.insert(helmDay)
        }

        var bodyCompositionByDay: [HelmDay: BodyComposition] = [:]
        for helmDay in try store.bodyComposition.listDays() where helmDay >= startDay && helmDay <= endDay {
            let records = try store.bodyComposition.fetch(for: helmDay)
            if let merged = Self.mergeBodyComposition(records) {
                bodyCompositionByDay[helmDay] = merged
                days.insert(helmDay)
            }
        }

        let baselineState = decodeBaselineState(from: try store.readiness.fetchBaselineJSON())
        let baselines = [
            baselinesText(from: baselineState),
            try bodyCompositionSummary(
                from: store,
                endingAt: endDay,
                calendar: calendar
            )
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        let chronicHRV = baselineState?.hrvChronic?.mean

        let recent = try days.sorted().map { helmDay in
            let loggingComplete = (try? store.nutritionLogStatus.isLoggingComplete(helmDay: helmDay)) ?? false
            return CoachContextDay(
                helmDay: helmDay,
                text: dayText(
                    helmDay: helmDay,
                    metrics: metricsByDay[helmDay],
                    readiness: readinessByDay[helmDay],
                    nutrition: try store.nutrition.fetchDay(helmDay: helmDay),
                    workouts: workoutsByDay[helmDay] ?? [],
                    sleepHours: try store.sleep.totalSleepHours(for: helmDay, calendar: calendar),
                    bodyComposition: bodyCompositionByDay[helmDay],
                    loggingComplete: loggingComplete,
                    chronicHRVMilliseconds: chronicHRV
                )
            )
        }

        let recentWorkouts = try recentWorkoutsBlock(from: store, limit: 5)
        let trainingPlanSnapshot = try trainingPlanSnapshotBlock(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let weekAheadStart = endDay.mondayOfSameWeek(calendar: calendar)
        let weekAheadSchedule = try weekAheadScheduleBlock(
            from: store,
            startingAt: weekAheadStart,
            through: endDay.adding(days: 6, calendar: calendar),
            calendar: calendar,
            busyDayHints: busyDayHints
        )
        let nutritionDiary = await CoachNutritionContextBuilder.diaryBlock(
            from: store,
            for: endDay,
            prescriptionSummary: nil,
            calendar: calendar,
            cutoff: cutoff
        )
        let weeklyBudget = await CoachNutritionContextBuilder.weeklyBudgetBlock(
            from: store,
            for: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        var nutritionWithWeekly = nutritionDiary
        if let budget = weeklyBudget, !budget.isEmpty {
            nutritionWithWeekly = nutritionDiary + "\n\n# Weekly Budget\n" + budget
        }

        return CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence,
            groupedEvidence: groupedEvidence,
            recent: recent,
            recentWorkouts: recentWorkouts,
            trainingPlanSnapshot: trainingPlanSnapshot,
            weekAheadSchedule: weekAheadSchedule,
            nutritionDiary: nutritionWithWeekly,
            todayPrescription: todayPrescription,
            prescriptionLoadSummary: prescriptionLoadSummary,
            volumeStateSummary: volumeStateSummary,
            engineProfile: engineProfile,
            moduleSummaries: moduleSummaries,
            recentSessionOutcomes: recentSessionOutcomes,
            freshness: freshness
        )
    }

    /// Compact sleep-stage detail for recovery_query sleepDetail / day lookups.
    public static func sleepDetailText(
        from store: PersistenceStore,
        helmDay: HelmDay,
        calendar: Calendar = .current
    ) throws -> String {
        guard let summary = try store.sleep.nightSummary(forWakeDay: helmDay, calendar: calendar) else {
            return "day=\(helmDay.formatted)\nsleep=none"
        }
        var parts: [String] = ["day=\(helmDay.formatted)"]
        if let asleep = summary.asleepHours {
            parts.append("sleep=\(SleepDurationFormatting.hoursAndMinutes(from: asleep))")
        }
        if let inBed = summary.inBedHours {
            parts.append("inBed=\(SleepDurationFormatting.hoursAndMinutes(from: inBed))")
        }
        if let deep = summary.deepMinutes {
            parts.append("deepMin=\(format(deep))")
        }
        if let rem = summary.remMinutes {
            parts.append("remMin=\(format(rem))")
        }
        if let awake = summary.awakeMinutes {
            parts.append("awakeMin=\(format(awake))")
        }
        if let efficiency = summary.efficiency {
            parts.append("efficiency=\(format(efficiency * 100))%")
        }
        return parts.joined(separator: " ")
    }

    private static func trainingPlanSnapshotBlock(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) throws -> String {
        let settings = try store.trainingPlan.load()
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate
        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let catalogRows = try store.exercises.fetchCatalogRows()
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let plannedToday = try store.plan.fetchPlannedWorkouts(from: endDay, through: endDay)
        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: endDay, calendar: calendar)
        let storedOverrides = (try? store.scheduleOverrides.load()) ?? .empty
        let overrides = ScheduleWeekOverrides.fromStored(storedOverrides, weekStart: weekStart)
        let todaySplit: SessionSplitKind?
        if let record = plannedToday.first,
           let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON),
           let kind = SessionSplitKind(rawValue: payload.splitKind) {
            todaySplit = kind
        } else if plannedToday.isEmpty {
            todaySplit = nil
        } else {
            let schedule = SchedulePlanner.plan(
                for: endDay,
                emphasis: settings.phaseGoal.emphasis,
                history: history,
                muscleMaps: muscleMaps,
                calendar: calendar,
                sessionsPerWeek: settings.daysPerWeek,
                dayKindRotation: TrainingPlanShape.dayKindRotation(from: settings),
                overrides: overrides
            )
            todaySplit = schedule.splitKind
        }
        let completedThisWeek = PrescriptionHistoryBuilder.completedSessionsThisWeek(
            in: history,
            through: endDay
        )
        let mesocycleState = decodeMesocycleState(from: try store.plan.loadMesocycleStateJSON())
        let ledger = PlanKit.rollingHardSetTotals(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            endingAt: endDay
        )

        var overrideNote: String?
        if overrides.isEmpty == false {
            var parts: [String] = []
            if overrides.deferredKinds.isEmpty == false {
                parts.append("deferred=\(overrides.deferredKinds.map(\.label).sorted().joined(separator: ","))")
            }
            if overrides.pinnedByDay.isEmpty == false {
                let pins = overrides.pinnedByDay
                    .map { "\($0.key.formatted):\($0.value.label)" }
                    .sorted()
                    .joined(separator: ",")
                parts.append("pins=\(pins)")
            }
            if overrides.restDays.isEmpty == false {
                parts.append("rest=\(overrides.restDays.map(\.formatted).sorted().joined(separator: ","))")
            }
            if let reason = overrides.reason {
                parts.append("reason=\(reason)")
            }
            overrideNote = parts.joined(separator: "; ")
        }

        return TrainingPlanCoachContext.build(
            from: TrainingPlanCoachContext.Input(
                emphasis: settings.phaseGoal.emphasis,
                todaySplit: todaySplit,
                weeklyLedger: ledger,
                mesocycleState: mesocycleState,
                experience: experience,
                remainingSessionsThisWeek: SessionSplitPlanner.remainingSessionsThisWeek(
                    completedThisWeek: completedThisWeek,
                    plannedPerWeek: settings.daysPerWeek
                ),
                pendingReactiveDeload: mesocycleState?.pendingReactiveDeload ?? false,
                sessionDurationMinutes: settings.sessionDurationMinutes,
                programTemplate: settings.programTemplateRaw,
                daysPerWeek: settings.daysPerWeek,
                weekRotation: TrainingPlanShape.dayKindRotation(from: settings).map(\.label),
                allowedEquipment: MethodologyPreferences.parse(from: try store.memoryProfile.load().preferences).preferences.allowedEquipment,
                scheduleOverrideNote: overrideNote
            )
        )
    }

    private static func weekAheadScheduleBlock(
        from store: PersistenceStore,
        startingAt startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar,
        busyDayHints: [HelmDay: String]
    ) throws -> String {
        let dayCount = max(1, startDay.days(to: endDay, calendar: calendar) + 1)
        let records = try store.plan.fetchPlannedWorkouts(from: startDay, through: endDay)
        let recordsByDay = Dictionary(
            uniqueKeysWithValues: try records.map { record in
                (try record.decodedHelmDay(), record)
            }
        )
        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay,
            calendar: calendar
        )
        let completedDays = Set(history.sessions.map(\.helmDay))
        let settings = try store.trainingPlan.load()
        let rotation = TrainingPlanShape.dayKindRotation(from: settings)
        let catalogRows = try store.exercises.fetchCatalogRows()
        let familiar = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiar
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: startDay, calendar: calendar)
        let storedOverrides = (try? store.scheduleOverrides.load()) ?? .empty
        let overrides = ScheduleWeekOverrides.fromStored(storedOverrides, weekStart: weekStart)

        var lines = [
            "horizon_days=\(dayCount)",
            "iso_week_start=\(weekStart.formatted)"
        ]
        if overrides.isEmpty == false {
            if let reason = overrides.reason {
                lines.append("schedule_override=\(reason)")
            }
            if overrides.deferredKinds.isEmpty == false {
                lines.append(
                    "deferred_kinds=\(overrides.deferredKinds.map(\.label).sorted().joined(separator: ","))"
                )
            }
        }
        for offset in 0 ..< dayCount {
            let day = startDay.adding(days: offset, calendar: calendar)
            let busy = busyDayHints[day].map { " busy=\($0)" } ?? ""
            let pin = overrides.pinnedByDay[day].map { " pin=\($0.label)" } ?? ""
            let forcedRest = overrides.restDays.contains(day) ? " override=rest" : ""
            if let record = recordsByDay[day],
               let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON) {
                let note = payload.primaryNote.map { " note=\($0)" } ?? ""
                let done = completedDays.contains(day) ? " logged=true" : ""
                lines.append(
                    "- \(day.formatted): \(payload.splitLabel) status=\(record.status)\(note)\(done)\(pin)\(busy)"
                )
            } else if completedDays.contains(day) {
                let label = inferredSplitLabel(
                    day: day,
                    history: history,
                    muscleMaps: muscleMaps,
                    rotation: rotation
                )
                lines.append("- \(day.formatted): \(label) status=completed note=logged_off_slot\(busy)")
            } else {
                lines.append("- \(day.formatted): Rest\(forcedRest)\(pin)\(busy)")
            }
        }
        if busyDayHints.isEmpty {
            lines.append("calendar_busy=none_or_unavailable")
        }
        return lines.joined(separator: "\n")
    }

    private static func inferredSplitLabel(
        day: HelmDay,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        rotation: [TrainingDayKind]
    ) -> String {
        guard let session = history.sessions.first(where: { $0.helmDay == day }) else {
            return "Session"
        }
        var muscles = Set<MuscleGroup>()
        for exerciseID in Set(session.sets.map(\.exerciseID)) {
            guard let map = muscleMaps[exerciseID] else { continue }
            for contribution in map.contributions where contribution.fraction >= 0.25 {
                muscles.insert(contribution.muscle)
            }
        }
        let among = rotation.isEmpty ? Array(TrainingDayKind.allCases) : rotation
        return TrainingDayKind.bestMatch(muscles: muscles, among: among)?.label ?? "Session"
    }

    private static func decodeMesocycleState(from json: String?) -> MesocycleState? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MesocycleState.self, from: data)
    }

    private static func recentWorkoutsBlock(
        from store: PersistenceStore,
        limit: Int
    ) throws -> String {
        let summaries = try store.workoutSessions.listSummaries(limit: limit)
        guard !summaries.isEmpty else { return "" }

        var blocks: [String] = []
        for summary in summaries {
            if summary.source == .healthKit {
                blocks.append(formatHealthKitWorkout(summary))
            } else {
                guard let draft = try store.workoutSessions.fetch(id: summary.id) else { continue }
                let names = try store.exercises.displayNames(for: draft.exercises.map(\.exerciseID))
                blocks.append(WorkoutExportFormatter.formatForCoachContext(draft: draft, displayNames: names))
            }
        }
        return blocks.joined(separator: "\n\n---\n\n")
    }

    private static func formatHealthKitWorkout(_ summary: WorkoutSessionSummary) -> String {
        var parts: [String] = [
            "workout=\"\(summary.title ?? "Workout")\" source=health_kit",
        ]
        if let ended = summary.endedAt {
            let seconds = Int(ended.timeIntervalSince(summary.startedAt))
            parts.append("duration_s=\(seconds)")
        }
        if let kcal = summary.hkActiveEnergyKilocalories {
            parts.append("energy_kcal=\(Int(kcal))")
        }
        if let distance = summary.hkTotalDistanceMeters {
            parts.append("distance_m=\(Int(distance))")
        }
        parts.append("started=\(ISO8601DateFormatter().string(from: summary.startedAt))")
        return parts.joined(separator: " ")
    }

    public static func bundledMethodologyEvidence() -> [EvidenceRecord] {
        MethodologyEvidenceSupport.allRecords
    }

    private static func bodyCompositionSummary(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar
    ) throws -> String {
        let yesterday = endDay.adding(days: -1, calendar: calendar)
        var lines: [String] = []
        var daysCovered = Set<HelmDay>()

        func appendDay(_ helmDay: HelmDay, _ composition: BodyComposition) {
            var line = "\(helmDay.formatted) weight=\(format(composition.mass.kilograms))kg"
            if let bf = composition.bodyFatPercentage {
                line += " bodyfat=\(format(bf))%"
            }
            lines.append(line)
            daysCovered.insert(helmDay)
        }

        if let today = mergeBodyComposition(try store.bodyComposition.fetch(for: endDay)) {
            appendDay(endDay, today)
        }
        if let prior = mergeBodyComposition(try store.bodyComposition.fetch(for: yesterday)) {
            appendDay(yesterday, prior)
        }

        if let latestFat = try store.bodyComposition.fetchLatestWithBodyFat(onOrBefore: endDay),
           let fat = latestFat.bodyFatPercentage,
           !daysCovered.contains(latestFat.helmDay) {
            lines.append(
                "latest bodyfat=\(format(fat))% on \(latestFat.helmDay.formatted)"
            )
        } else if lines.isEmpty,
                  let latest = try store.bodyComposition.fetchLatest(onOrBefore: endDay, limit: 1).first {
            var line = "latest weight=\(format(latest.mass.kilograms))kg on \(latest.helmDay.formatted)"
            if let bf = latest.bodyFatPercentage {
                line += " bodyfat=\(format(bf))%"
            }
            lines.append(line)
        }

        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n")
    }

    private static func dayText(
        helmDay: HelmDay,
        metrics: DailyMetrics?,
        readiness: ReadinessScoreSnippet?,
        nutrition: NutritionDay?,
        workouts: [WorkoutSessionSummary],
        sleepHours: Double?,
        bodyComposition: BodyComposition?,
        loggingComplete: Bool,
        chronicHRVMilliseconds: Double?
    ) -> String {
        var parts: [String] = []

        if let readiness {
            parts.append("readiness=\(readiness.score)")
            if let band = readiness.band {
                parts.append("readiness_band=\(band.rawValue)")
            }
            if let confidence = readiness.confidence {
                parts.append("confidence=\(confidence.rawValue)")
            }
            if let hrvBand = readiness.hrvBand {
                parts.append("hrv_band=\(hrvBand.rawValue)")
            }
            if let raw = readiness.contributors?.rawScore {
                parts.append("rawScore=\(format(raw))")
            }
            if let damped = readiness.contributors?.dampedScore {
                parts.append("dampedScore=\(format(damped))")
            }
            if let zComposite = readiness.contributors?.zComposite {
                parts.append("zComposite=\(formatSigned(zComposite))")
            }
            if let validNights = readiness.validNights {
                parts.append("validNights=\(validNights)")
            }
            if let confidenceValue = readiness.confidenceValue {
                parts.append("confidenceValue=\(format(confidenceValue))")
            }
            if let stabilityScore = readiness.stabilityScore {
                parts.append("stabilityScore=\(format(stabilityScore))")
            }
            if let hrv = readiness.effectiveHRVMilliseconds {
                parts.append("hrv=\(format(hrv))ms")
                if let chronic = chronicHRVMilliseconds {
                    parts.append("hrvVsChronic=\(formatSigned(hrv - chronic))ms")
                }
            } else if let hrv = metrics?.hrvSDNN?.milliseconds {
                parts.append("hrv=\(hrv)ms")
                if let chronic = chronicHRVMilliseconds {
                    parts.append("hrvVsChronic=\(formatSigned(Double(hrv) - chronic))ms")
                }
            }
            if let rhr = readiness.restingHeartRate ?? metrics?.restingHeartRate {
                parts.append("rhr=\(rhr)")
            }
            appendContributorHints(from: readiness.contributors, into: &parts)
        } else if let metrics {
            if let hrv = metrics.hrvSDNN?.milliseconds {
                parts.append("hrv=\(hrv)ms")
                if let chronic = chronicHRVMilliseconds {
                    parts.append("hrvVsChronic=\(formatSigned(Double(hrv) - chronic))ms")
                }
            }
            if let rhr = metrics.restingHeartRate {
                parts.append("rhr=\(rhr)")
            }
        }

        if let sleepHours {
            parts.append("sleep=\(SleepDurationFormatting.hoursAndMinutes(from: sleepHours))")
        }

        if let trimp = metrics?.priorDayTRIMP {
            parts.append("trimp=\(format(trimp))")
        }

        if let resp = metrics?.respiratoryRate {
            parts.append("resp=\(format(resp))")
        }
        if let temp = metrics?.wristTemperatureDeltaCelsius {
            parts.append("tempDeltaC=\(format(temp))")
        }

        if let steps = metrics?.stepCount {
            parts.append("steps=\(steps)")
        }
        if let restingKcal = metrics?.restingEnergyKcal {
            parts.append("resting_energy_kcal=\(format(restingKcal))")
        }

        if let nutrition {
            parts.append("intake_logging_complete=\(loggingComplete)")
            if !loggingComplete {
                parts.append("intake_may_be_incomplete=true")
            }
            if let kcal = nutrition.totalEnergy?.kilocalories {
                parts.append("kcal=\(format(kcal))")
            }
            if let protein = nutrition.totalProteinGrams {
                parts.append("protein=\(format(protein))g")
            }
        }

        if let activeEnergy = metrics?.activeEnergy {
            parts.append("active_energy_kcal=\(format(activeEnergy.kilocalories))")
        }

        if let bodyComposition {
            parts.append("weight=\(format(bodyComposition.mass.kilograms))kg")
            if let bodyFat = bodyComposition.bodyFatPercentage {
                parts.append("bodyfat=\(format(bodyFat))%")
            }
        }

        if !workouts.isEmpty {
            let strengthWorkouts = workouts.filter { $0.source != .healthKit }
            let hkWorkouts = workouts.filter { $0.source == .healthKit }

            if !strengthWorkouts.isEmpty {
                let titles = strengthWorkouts.map { $0.title ?? "Workout" }.joined(separator: ", ")
                let setCount = strengthWorkouts.reduce(0) { $0 + $1.totalSetCount }
                parts.append("workout=\"\(titles)\" sets=\(setCount)")
            }

            for hk in hkWorkouts {
                var hkParts: [String] = ["cardio=\"\(hk.title ?? "Workout")\""]
                if let ended = hk.endedAt {
                    let seconds = Int(ended.timeIntervalSince(hk.startedAt))
                    hkParts.append("duration_s=\(seconds)")
                }
                if let kcal = hk.hkActiveEnergyKilocalories {
                    hkParts.append("energy_kcal=\(Int(kcal))")
                }
                parts.append(hkParts.joined(separator: " "))
            }
        }

        if parts.isEmpty {
            return "no_data"
        }

        return parts.joined(separator: " ")
    }

    private static func appendContributorHints(
        from contributors: ReadinessContributorBreakdown?,
        into parts: inout [String]
    ) {
        guard let contributors else { return }
        if let z = contributors.zHRV { parts.append("zHRV=\(formatSigned(z))") }
        if let z = contributors.zRestingHR { parts.append("zRHR=\(formatSigned(z))") }
        if let z = contributors.zSleep { parts.append("zSleep=\(formatSigned(z))") }
        if let z = contributors.zRespiratory { parts.append("zResp=\(formatSigned(z))") }
        if let z = contributors.zTemperature { parts.append("zTemp=\(formatSigned(z))") }
        if let z = contributors.zStrain { parts.append("zStrain=\(formatSigned(z))") }
    }

    /// Merge multiple body composition records for the same day into one.
    /// Mass is taken from a record with non-zero mass; bodyFat from any record that has it.
    private static func mergeBodyComposition(_ records: [BodyComposition]) -> BodyComposition? {
        guard !records.isEmpty else { return nil }
        let mass = records.first(where: { $0.mass.kilograms > 0 })?.mass ?? records.first!.mass
        let fat = records.first(where: { $0.bodyFatPercentage != nil })?.bodyFatPercentage
        let latestMeasured = records.map(\.measuredAt).max() ?? records.first!.measuredAt
        let first = records.first!
        return BodyComposition(
            id: first.id,
            helmDay: first.helmDay,
            mass: mass,
            bodyFatPercentage: fat,
            measuredAt: latestMeasured
        )
    }

    private static func baselinesText(from state: ReadinessBaselineState?) -> String {
        guard let state else { return "" }

        var lines: [String] = []
        if let hrv = state.hrvChronic {
            lines.append("hrvChronicMs=\(format(hrv.mean))")
        }
        if let restingHR = state.restingHR {
            lines.append("restingHR=\(format(restingHR.mean))")
        }
        if let sleepDuration = state.sleepDuration {
            lines.append("sleepDurationBaselineMs=\(format(sleepDuration.mean))")
        }
        if let sleepEfficiency = state.sleepEfficiency {
            lines.append("sleepEfficiencyBaseline=\(format(sleepEfficiency.mean * 100))%")
        }
        if let sleepDebt = state.sleepDebt {
            lines.append("sleepDebtBaselineMs=\(format(sleepDebt.mean))")
        }
        if let resp = state.respiratoryRate {
            lines.append("respRateBaseline=\(format(resp.mean))")
        }
        if let temp = state.wristTemperature {
            lines.append("wristTempBaselineC=\(format(temp.mean))")
        }
        if let trimp = state.trimpP75 {
            lines.append("trimpP75=\(format(trimp))")
        }
        if state.seededNightCount > 0 {
            lines.append("seededNights=\(state.seededNightCount)")
        }
        return lines.joined(separator: "\n")
    }

    private static func decodeBaselineState(from json: String?) -> ReadinessBaselineState? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessBaselineState.self, from: data)
    }

    private static func decodeScoreSnippet(from json: String) -> ReadinessScoreSnippet? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessScoreSnippet.self, from: data)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private static func formatSigned(_ value: Double) -> String {
        let body = format(abs(value))
        if value > 0 { return "+\(body)" }
        if value < 0 { return "-\(body)" }
        return body
    }
}

private struct ReadinessScoreSnippet: Decodable {
    let score: Int
    let band: ReadinessBand?
    let confidence: ReadinessConfidence?
    let confidenceValue: Double?
    let hrvBand: HRVZBand?
    let validNights: Int?
    let stabilityScore: Double?
    let contributors: ReadinessContributorBreakdown?
    let effectiveHRVMilliseconds: Double?
    let restingHeartRate: Int?
}
