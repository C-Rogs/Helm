import CoachLLM
import Core
import Foundation
import Persistence
import ReadinessKit

/// Maps persisted health and training rows into coach context days.
public enum CoachContextAssembler {
    public static let defaultLookbackDays = 14

    public static func assemble(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = defaultLookbackDays,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> CoachContextDays {
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

        let recent = try days.sorted().map { helmDay in
            CoachContextDay(
                helmDay: helmDay,
                text: dayText(
                    helmDay: helmDay,
                    metrics: metricsByDay[helmDay],
                    readiness: readinessByDay[helmDay],
                    nutrition: try store.nutrition.fetchDay(helmDay: helmDay),
                    workouts: workoutsByDay[helmDay] ?? [],
                    sleepRecords: try store.sleep.fetch(for: helmDay)
                )
            )
        }

        return CoachContextDays(
            readinessBaselines: baselinesText(from: try store.readiness.fetchBaselineJSON()),
            evidence: [],
            recent: recent
        )
    }

    private static func dayText(
        helmDay: HelmDay,
        metrics: DailyMetrics?,
        readiness: ReadinessScoreSnippet?,
        nutrition: NutritionDay?,
        workouts: [WorkoutSessionSummary],
        sleepRecords: [SleepRecord]
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

        if let sleepHours = totalSleepHours(from: sleepRecords) {
            parts.append("sleep=\(format(sleepHours))h")
        }

        if let trimp = metrics?.priorDayTRIMP {
            parts.append("trimp=\(format(trimp))")
        }

        if let nutrition {
            if let kcal = nutrition.totalEnergy?.kilocalories {
                parts.append("kcal=\(format(kcal))")
            }
            if let protein = nutrition.totalProteinGrams {
                parts.append("protein=\(format(protein))g")
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

    private static func totalSleepHours(from records: [SleepRecord]) -> Double? {
        guard !records.isEmpty else { return nil }
        let seconds = records.reduce(0.0) { $0 + $1.duration }
        return seconds / 3_600
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
