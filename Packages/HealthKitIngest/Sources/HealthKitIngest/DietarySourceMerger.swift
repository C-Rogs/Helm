import Core
import Foundation

public enum DietarySourceMode: String, Sendable, CaseIterable {
    case mergeExternal
    case helmOnly

    public var displayName: String {
        switch self {
        case .mergeExternal:
            "Merge external"
        case .helmOnly:
            "Helm only"
        }
    }
}

/// Deduplicates overlapping HealthKit dietary entries during the MFP transition.
public enum DietarySourceMerger {
    public static let timeWindowSeconds: TimeInterval = 15 * 60
    public static let kcalToleranceFraction = 0.10

    public static func isHelmNative(_ meal: MealRecord) -> Bool {
        meal.source != .healthKit
    }

    public static func meals(
        from allMeals: [MealRecord],
        mode: DietarySourceMode
    ) -> [MealRecord] {
        switch mode {
        case .helmOnly:
            allMeals.filter(isHelmNative)
        case .mergeExternal:
            deduplicateOverlapping(allMeals)
        }
    }

    public static func overlaps(_ helm: MealRecord, _ external: MealRecord) -> Bool {
        guard isHelmNative(helm), !isHelmNative(external) else { return false }

        let timeDelta = abs(helm.loggedAt.timeIntervalSince(external.loggedAt))
        guard timeDelta <= timeWindowSeconds else { return false }

        guard
            let helmKcal = helm.energy?.kilocalories,
            let externalKcal = external.energy?.kilocalories,
            helmKcal > 0,
            externalKcal > 0
        else {
            return false
        }

        let ratio = externalKcal / helmKcal
        return ratio >= (1 - kcalToleranceFraction) && ratio <= (1 + kcalToleranceFraction)
    }

    public static func shouldSkipExternalIngest(
        _ external: MealRecord,
        existingMeals: [MealRecord],
        mode: DietarySourceMode
    ) -> Bool {
        switch mode {
        case .helmOnly:
            return true
        case .mergeExternal:
            let helmMeals = existingMeals.filter(isHelmNative)
            return helmMeals.contains { overlaps($0, external) }
        }
    }

    private static func deduplicateOverlapping(_ meals: [MealRecord]) -> [MealRecord] {
        let helmMeals = meals.filter(isHelmNative)
        let externalMeals = meals.filter { !isHelmNative($0) }
        let keptExternal = externalMeals.filter { external in
            !helmMeals.contains { overlaps($0, external) }
        }
        return helmMeals + keptExternal
    }
}
