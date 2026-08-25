import Core
import Foundation
import Persistence

public struct NutritionDayDemandService: Sendable {
    private let persistence: PersistenceStore

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    /// Resolves one day using the canonical priority: explicit override, planned
    /// training/cardio, then ordinary demand (or office when supplied by caller).
    public func resolve(
        for day: HelmDay,
        plannedCardioDays: Set<HelmDay> = [],
        ordinaryDemand: NutritionDayDemand = .ordinary
    ) throws -> ResolvedNutritionDayDemand {
        if let override = try persistence.nutritionDayDemandOverrides.fetch(for: day) {
            return ResolvedNutritionDayDemand(
                helmDay: day,
                demand: override.demand,
                source: .explicitOverride
            )
        }

        let planned = try persistence.plan.fetchPlannedWorkouts(from: day, through: day)
        if planned.contains(where: { $0.status != "skipped" }) {
            return ResolvedNutritionDayDemand(helmDay: day, demand: .training, source: .plannedTraining)
        }

        if plannedCardioDays.contains(day) {
            return ResolvedNutritionDayDemand(helmDay: day, demand: .cardio, source: .plannedCardio)
        }

        let fallback: NutritionDayDemand = ordinaryDemand == .office ? .office : .ordinary
        return ResolvedNutritionDayDemand(helmDay: day, demand: fallback, source: .ordinary)
    }

    public func setExplicitOverride(
        _ demand: NutritionDayDemand,
        for day: HelmDay,
        updatedAt: Date = Date()
    ) throws {
        try persistence.nutritionDayDemandOverrides.save(
            NutritionDayDemandOverride(helmDay: day, demand: demand, updatedAt: updatedAt)
        )
    }

    public func clearExplicitOverride(for day: HelmDay) throws {
        try persistence.nutritionDayDemandOverrides.delete(for: day)
    }
}
