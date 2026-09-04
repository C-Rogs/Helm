import Core
import Foundation
import Persistence
import PatternKit
import ReadinessKit

public enum DayFeatureAssembler {
    public static func assemble(
        from store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [DayFeatureRow] {
        var daySet = Set<HelmDay>()
        daySet.formUnion(try store.dailyMetrics.listDays())
        daySet.formUnion(try store.sleep.listDays())
        daySet.formUnion(try store.nutrition.listDays())
        daySet.formUnion(try store.bodyComposition.listDays())
        guard let start = daySet.min(), let end = daySet.max() else { return [] }

        let metrics = Dictionary(
            uniqueKeysWithValues: try store.dailyMetrics.fetchRange(from: start, through: end).map { ($0.helmDay, $0) }
        )
        let nutrition = Dictionary(
            uniqueKeysWithValues: try store.nutrition.fetchRange(from: start, through: end).map { ($0.helmDay, $0) }
        )
        let meals = Dictionary(grouping: try store.nutrition.fetchMealsInRange(from: start, through: end), by: \.helmDay)
        let readiness = Dictionary(
            uniqueKeysWithValues: try store.readiness.fetchScoreRange(from: start, through: end).compactMap { day, json in
                decodeScore(json).map { (day, $0) }
            }
        )
        let demands = Dictionary(
            uniqueKeysWithValues: try store.nutritionDayDemandOverrides.fetch(from: start, through: end).map {
                ($0.helmDay, $0.demand.rawValue)
            }
        )
        let weights = Dictionary(
            try store.bodyComposition.fetchDailyWeights(
                endingAt: end,
                limit: 10_000
            ).filter { $0.0 >= start },
            uniquingKeysWith: { _, newer in newer }
        )
        let sessions = Dictionary(
            grouping: try store.workoutSessions.fetchCompletedSummaries().filter { summary in
                let day = HelmDay.day(for: summary.startedAt, cutoff: cutoff, calendar: calendar)
                return day >= start && day <= end
            }
        ) { HelmDay.day(for: $0.startedAt, cutoff: cutoff, calendar: calendar) }

        let sleepStart = SleepAggregation.sleepWindowStart(
            for: calendar.date(from: start.dateComponents()) ?? Date.distantPast,
            calendar: calendar
        )
        let lastWake = calendar.date(from: end.dateComponents()) ?? Date.distantPast
        let sleepEnd = SleepAggregation.sleepWindowEnd(for: lastWake, calendar: calendar)
        let sleepRecords = try store.sleep.fetchOverlapping(start: sleepStart, end: sleepEnd)

        var rows: [DayFeatureRow] = []
        var day = start
        while day <= end {
            let wakeDate = calendar.date(from: day.dateComponents())
            let weekday = wakeDate.map { calendar.component(.weekday, from: $0) } ?? 1
            let windowStart = wakeDate.map { SleepAggregation.sleepWindowStart(for: $0, calendar: calendar) }
            let windowEnd = wakeDate.map { SleepAggregation.sleepWindowEnd(for: $0, calendar: calendar) }
            let sleep: SleepNightSummary? = {
                guard let windowStart, let windowEnd else { return nil }
                let summary = SleepAggregation.nightSummary(
                    from: sleepRecords,
                    windowStart: windowStart,
                    windowEnd: windowEnd
                )
                return summary.asleepHours == nil ? nil : summary
            }()

            let dayMeals = meals[day] ?? []
            let daySessions = sessions[day] ?? []
            let metric = metrics[day]
            let nut = nutrition[day]
            let score = readiness[day]

            let dietKcal = DayFeatureMissingness.dietValue(
                nut?.totalEnergy?.kilocalories ?? metric?.dietaryEnergy?.kilocalories
            )
            let dietProtein = DayFeatureMissingness.dietValue(
                nut?.totalProteinGrams ?? metric?.dietaryProteinGrams
            )
            let workoutMinutes = sessionMinutes(daySessions)
            let sessionVolume = daySessions.reduce(0.0) { $0 + $1.totalVolumeKilograms }
            let prescribedVolume = daySessions.compactMap(\.prescribedVolumeKilograms).reduce(0, +)
            let hasPrescription = daySessions.contains { $0.prescribedVolumeKilograms != nil }
            let hardSets = daySessions.reduce(0) { $0 + $1.totalSetCount }
            let eatTo = nut?.eatToKilocalories
            let energyResidual: Double? = {
                guard let dietKcal, let eatTo else { return nil }
                return dietKcal - eatTo
            }()
            let volumeResidual: Double? = hasPrescription ? sessionVolume - prescribedVolume : nil
            let trainingDay = workoutMinutes > 0 || sessionVolume > 0 || hardSets > 0

            rows.append(
                DayFeatureRow(
                    helmDay: day,
                    weekday: weekday,
                    alcohol: dayMeals.contains { $0.source == .alcohol } ? true : (dayMeals.isEmpty ? nil : false),
                    breakfastLogged: dayMeals.contains { $0.bucket == .breakfast } ? true : (dayMeals.isEmpty ? nil : false),
                    trainingDay: trainingDay,
                    dietEnergyKcal: dietKcal,
                    dietProteinG: dietProtein,
                    sleepAsleepMin: sleep?.asleepHours.map { $0 * 60 },
                    sleepRemMin: sleep?.remMinutes,
                    sleepEfficiency: sleep?.efficiency,
                    hrvSdnn: metric?.hrvSDNN.map { Double($0.milliseconds) },
                    restingHr: metric?.restingHeartRate.map(Double.init) ?? score?.restingHeartRate.map(Double.init),
                    arcScore: score.map { Double($0.score) },
                    arcBand: score?.band.rawValue,
                    bodyMassKg: weights[day],
                    workoutMinutes: workoutMinutes > 0 ? workoutMinutes : nil,
                    sessionVolumeKg: sessionVolume > 0 ? sessionVolume : nil,
                    priorDayTrimp: metric?.priorDayTRIMP,
                    dayDemand: demands[day],
                    hardSetCount: hardSets > 0 ? Double(hardSets) : nil,
                    energyResidual: energyResidual,
                    volumeResidual: volumeResidual
                )
            )
            day = day.adding(days: 1, calendar: calendar)
        }
        return rows
    }

    private static func sessionMinutes(_ sessions: [WorkoutSessionSummary]) -> Double {
        sessions.reduce(0.0) { total, session in
            guard let ended = session.endedAt else { return total }
            return total + max(0, ended.timeIntervalSince(session.startedAt) / 60)
        }
    }

    private static func decodeScore(_ json: String) -> ReadinessScore? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessScore.self, from: data)
    }
}
