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
        evidence: [EvidenceRecord] = bundledMethodologyEvidence()
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
            if let latest = try store.bodyComposition.fetch(for: helmDay).last {
                bodyCompositionByDay[helmDay] = latest
                days.insert(helmDay)
            }
        }

        let baselines = [
            baselinesText(from: try store.readiness.fetchBaselineJSON()),
            try bodyCompositionSummary(
                from: store,
                endingAt: endDay,
                calendar: calendar
            )
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

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
                    loggingComplete: loggingComplete
                )
            )
        }

        let recentWorkouts = try recentWorkoutsBlock(from: store, limit: 3)
        let trainingPlanSnapshot = try trainingPlanSnapshotBlock(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let nutritionDiary = await CoachNutritionContextBuilder.diaryBlock(
            from: store,
            for: endDay,
            prescriptionSummary: nil,
            calendar: calendar,
            cutoff: cutoff
        )

        return CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence,
            recent: recent,
            recentWorkouts: recentWorkouts,
            trainingPlanSnapshot: trainingPlanSnapshot,
            nutritionDiary: nutritionDiary
        )
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
        let schedule = SchedulePlanner.plan(
            for: endDay,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
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

        return TrainingPlanCoachContext.build(
            from: TrainingPlanCoachContext.Input(
                emphasis: settings.phaseGoal.emphasis,
                todaySplit: schedule.splitKind,
                weeklyLedger: ledger,
                mesocycleState: mesocycleState,
                experience: experience,
                remainingSessionsThisWeek: SessionSplitPlanner.remainingSessionsThisWeek(
                    completedThisWeek: completedThisWeek
                )
            )
        )
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
            guard let draft = try store.workoutSessions.fetch(id: summary.id) else { continue }
            let names = try store.exercises.displayNames(for: draft.exercises.map(\.exerciseID))
            blocks.append(WorkoutExportFormatter.formatForCoachContext(draft: draft, displayNames: names))
        }
        return blocks.joined(separator: "\n\n---\n\n")
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

        if let today = try store.bodyComposition.fetch(for: endDay).last {
            lines.append("\(endDay.formatted) weight=\(format(today.mass.kilograms))kg")
        }
        if let prior = try store.bodyComposition.fetch(for: yesterday).last {
            lines.append("\(yesterday.formatted) weight=\(format(prior.mass.kilograms))kg")
        } else if lines.isEmpty,
                  let latest = try store.bodyComposition.fetchLatest(onOrBefore: endDay, limit: 1).first {
            lines.append("latest weight=\(format(latest.mass.kilograms))kg on \(latest.helmDay.formatted)")
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
        loggingComplete: Bool
    ) -> String {
        var parts: [String] = []

        if let readiness {
            parts.append("readiness=\(readiness.score)")
            if let hrv = readiness.effectiveHRVMilliseconds {
                parts.append("hrv=\(format(hrv))ms")
            } else if let hrv = metrics?.hrvSDNN?.milliseconds {
                parts.append("hrv=\(hrv)ms")
            }
            if let rhr = readiness.restingHeartRate ?? metrics?.restingHeartRate {
                parts.append("rhr=\(rhr)")
            }
        } else if let metrics {
            if let hrv = metrics.hrvSDNN?.milliseconds {
                parts.append("hrv=\(hrv)ms")
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

        if let bodyComposition {
            parts.append("weight=\(format(bodyComposition.mass.kilograms))kg")
            if let bodyFat = bodyComposition.bodyFatPercentage {
                parts.append("bodyfat=\(format(bodyFat))%")
            }
        }

        if !workouts.isEmpty {
            let titles = workouts.map { $0.title ?? "Workout" }.joined(separator: ", ")
            let setCount = workouts.reduce(0) { $0 + $1.totalSetCount }
            parts.append("workout=\"\(titles)\" sets=\(setCount)")
        }

        if parts.isEmpty {
            return "no_data"
        }

        return parts.joined(separator: " ")
    }

    private static func baselinesText(from json: String?) -> String {
        guard
            let json,
            let data = json.data(using: .utf8),
            let state = try? JSONDecoder().decode(ReadinessBaselineState.self, from: data)
        else {
            return ""
        }

        var lines: [String] = []
        if let hrv = state.hrvChronic {
            lines.append("hrvChronicMs=\(format(hrv.mean))")
        }
        if let restingHR = state.restingHR {
            lines.append("restingHR=\(format(restingHR.mean))")
        }
        if state.seededNightCount > 0 {
            lines.append("seededNights=\(state.seededNightCount)")
        }
        return lines.joined(separator: "\n")
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
}

private struct ReadinessScoreSnippet: Decodable {
    let score: Int
    let effectiveHRVMilliseconds: Double?
    let restingHeartRate: Int?
}
