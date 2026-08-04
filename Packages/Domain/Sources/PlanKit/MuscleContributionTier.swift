import Foundation

/// Ledger tier for fractional hard-set credit (v1.2 volume ruler).
public enum MuscleContributionTier: String, Sendable, Hashable, Codable, CaseIterable {
    case primary
    case majorSynergist
    case minorSynergist
    case stabilizer

    public var credit: Double {
        switch self {
        case .primary: 1.0
        case .majorSynergist: 0.5
        case .minorSynergist: 0.25
        case .stabilizer: 0.0
        }
    }

    /// Infer tier from legacy fractional splits when explicit tier is absent.
    public static func inferred(from fraction: Double) -> MuscleContributionTier {
        if fraction >= 0.6 { return .primary }
        if fraction >= 0.3 { return .majorSynergist }
        if fraction >= 0.1 { return .minorSynergist }
        return .stabilizer
    }
}
