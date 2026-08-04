import Foundation
import ReadinessKit

/// Readiness-driven volume and intensity scaling for today's prescription.
public struct ReadinessGatingEffect: Sendable, Hashable, Codable {
    /// Target fraction of filled sets to keep after ordered trimming.
    public let volumeMultiplier: Double
    public let rpeCap: Double
    public let targetRPE: Double
    /// When true, `SessionAutoregulator` runs ordered trim instead of a global set multiplier in fill.
    public let usesOrderedVolumeTrim: Bool
    /// Last resort for depleted days: keep sets but cap RPE for technique/pump work.
    public let convertsRemainingToTechnique: Bool
    /// Optional rest-day nudge when recovery signals are severely suppressed.
    public let suggestsRest: Bool

    public init(
        volumeMultiplier: Double,
        rpeCap: Double,
        targetRPE: Double,
        usesOrderedVolumeTrim: Bool = false,
        convertsRemainingToTechnique: Bool = false,
        suggestsRest: Bool = false
    ) {
        self.volumeMultiplier = volumeMultiplier
        self.rpeCap = rpeCap
        self.targetRPE = targetRPE
        self.usesOrderedVolumeTrim = usesOrderedVolumeTrim
        self.convertsRemainingToTechnique = convertsRemainingToTechnique
        self.suggestsRest = suggestsRest
    }
}

public enum ReadinessGating {
    public static func effect(for readiness: ReadinessScore?) -> ReadinessGatingEffect {
        guard let readiness else {
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 8.5, targetRPE: 8.0)
        }
        switch readiness.band {
        case .depleted:
            // Ordered trim after slot fill: cap RPE, trim isolation, then compounds @ MEV floor, then technique.
            return ReadinessGatingEffect(
                volumeMultiplier: 0.7,
                rpeCap: 7.0,
                targetRPE: 6.5,
                usesOrderedVolumeTrim: true,
                convertsRemainingToTechnique: true,
                suggestsRest: readiness.score < 15
            )
        case .balanced:
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 8.5, targetRPE: 8.0)
        case .primed:
            // High readiness may lift intensity but never adds set volume beyond the mesocycle plan.
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 10.0, targetRPE: 9.0)
        }
    }
}
