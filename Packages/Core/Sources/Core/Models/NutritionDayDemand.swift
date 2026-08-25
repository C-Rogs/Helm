import Foundation

/// Canonical nutrition demand attached to a logical day.
public enum NutritionDayDemand: String, Sendable, Hashable, Codable, CaseIterable {
    case ordinary
    case office
    case training
    case cardio
    case social
    case party
    case highIntake = "high_intake"
}

/// User-authored metadata always takes precedence over inferred demand.
public struct NutritionDayDemandOverride: Sendable, Hashable, Codable, Identifiable {
    public let helmDay: HelmDay
    public let demand: NutritionDayDemand
    public let updatedAt: Date

    public var id: HelmDay { helmDay }

    public init(helmDay: HelmDay, demand: NutritionDayDemand, updatedAt: Date = Date()) {
        self.helmDay = helmDay
        self.demand = demand
        self.updatedAt = updatedAt
    }
}

public struct ResolvedNutritionDayDemand: Sendable, Hashable, Codable {
    public enum Source: String, Sendable, Hashable, Codable {
        case explicitOverride = "explicit_override"
        case plannedTraining
        case plannedCardio
        case ordinary
    }

    public let helmDay: HelmDay
    public let demand: NutritionDayDemand
    public let source: Source

    public init(helmDay: HelmDay, demand: NutritionDayDemand, source: Source) {
        self.helmDay = helmDay
        self.demand = demand
        self.source = source
    }
}
