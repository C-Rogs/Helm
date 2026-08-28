import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit

/// Grounded chart.v1 payloads from diary / volume ledger. Chat must not invent points.
public enum CoachChatChartBuilder: Sendable {
    public static func build(
        kind: CoachChatIntent.ChatChartKind,
        store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> ChartPayload {
        switch kind {
        case .weeklyCalories:
            return try weeklyNutritionChart(
                title: "Calories this week",
                unit: "kcal",
                reply: "Calories logged this week.",
                endingAt: endDay,
                calendar: calendar,
                store: store,
                value: { day in
                    nutritionValue(for: day, store: store, protein: false)
                }
            )
        case .weeklyProtein:
            return try weeklyNutritionChart(
                title: "Protein this week",
                unit: "g",
                reply: "Protein logged this week.",
                endingAt: endDay,
                calendar: calendar,
                store: store,
                value: { day in
                    nutritionValue(for: day, store: store, protein: true)
                }
            )
        case .hardSets:
            return try hardSetChart(
                store: store,
                endingAt: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
        }
    }

    public static func merge(_ chart: ChartPayload, into assembled: String) -> String {
        let prose = CoachChatTextFormatter.userFacingText(from: assembled)
        let reply = prose.isEmpty ? chart.reply : prose
        return ChartPayloadParser.persistText(reply: reply, payload: chart)
    }

    private static func weeklyNutritionChart(
        title: String,
        unit: String,
        reply: String,
        endingAt endDay: HelmDay,
        calendar: Calendar,
        store: PersistenceStore,
        value: (HelmDay) -> Double
    ) throws -> ChartPayload {
        let monday = endDay.mondayOfSameWeek(calendar: calendar)
        var points: [ChartPayload.Point] = []
        var anyLogged = false
        for offset in 0 ..< 7 {
            let day = monday.adding(days: offset, calendar: calendar)
            let amount = value(day)
            if amount > 0 { anyLogged = true }
            points.append(ChartPayload.Point(label: weekdayLabel(day, calendar: calendar), value: amount))
        }
        let resolvedReply = anyLogged ? reply : "Nothing logged this week yet."
        return ChartPayload(reply: resolvedReply, title: title, unit: unit, points: points)
    }

    private static func nutritionValue(
        for day: HelmDay,
        store: PersistenceStore,
        protein: Bool
    ) -> Double {
        if protein {
            if let grams = try? store.nutrition.fetchDay(helmDay: day)?.totalProteinGrams, grams > 0 {
                return grams
            }
            let meals = (try? store.nutrition.fetchMeals(for: day)) ?? []
            return meals.reduce(0) { $0 + ($1.proteinGrams ?? 0) }
        }
        if let kcal = try? store.nutrition.fetchDay(helmDay: day)?.totalEnergy?.kilocalories, kcal > 0 {
            return kcal
        }
        let meals = (try? store.nutrition.fetchMeals(for: day)) ?? []
        return meals.reduce(0) { $0 + ($1.energy?.kilocalories ?? 0) }
    }

    private static func hardSetChart(
        store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) throws -> ChartPayload {
        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let catalogRows = try store.exercises.fetchCatalogRows()
        let familiar = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiar
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let ledger = PlanKit.rollingHardSetTotals(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            endingAt: endDay
        )
        let points = MuscleGroup.allCases.map { muscle in
            ChartPayload.Point(
                label: muscle.rawValue.capitalized,
                value: ledger.totals[muscle, default: 0]
            )
        }
        let any = points.contains { $0.value > 0 }
        let reply = any
            ? "Hard-set volume this week by muscle."
            : "No hard sets logged this week yet."
        return ChartPayload(reply: reply, title: "Hard sets this week", unit: "sets", points: points)
    }

    private static func weekdayLabel(_ day: HelmDay, calendar: Calendar) -> String {
        guard let date = calendar.date(from: day.dateComponents()) else {
            return day.formatted
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
