import Core
import Foundation
import NutritionKit
import Persistence

enum NutritionTrendBuilder {
    static let weekLength = 7

    static func weekInputs(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = weekLength,
        calendar: Calendar = .current
    ) throws -> [NutritionTrendDayInput] {
        let startDay = endDay.adding(days: -(lookbackDays - 1), calendar: calendar)
        let nutritionDays = try store.nutrition.fetchRange(from: startDay, through: endDay)
        let nutritionByDay = Dictionary(uniqueKeysWithValues: nutritionDays.map { ($0.helmDay, $0) })

        var inputs: [NutritionTrendDayInput] = []
        var day = startDay
        while day <= endDay {
            let bodyMassKg = try store.bodyComposition.fetchLatest(onOrBefore: day, limit: 1).first?.mass.kilograms
            let loggedIntakeKcal = nutritionByDay[day]?.totalEnergy?.kilocalories
            inputs.append(
                NutritionTrendDayInput(
                    helmDay: day,
                    bodyMassKg: bodyMassKg,
                    loggedIntakeKcal: loggedIntakeKcal
                )
            )
            day = day.adding(days: 1, calendar: calendar)
        }
        return inputs
    }

    static func updatedTrend(
        from store: PersistenceStore,
        state: inout NutritionTrendState,
        through endDay: HelmDay,
        calendar: Calendar = .current
    ) throws -> NutritionTrendState {
        let weekDays = try weekInputs(from: store, endingAt: endDay, calendar: calendar)
        return NutritionKit.updateTrend(state: &state, weekDays: weekDays)
    }
}
