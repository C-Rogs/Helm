import Foundation
import ReadinessKit

/// Readiness-driven volume and intensity scaling for today's prescription.
public struct ReadinessGatingEffect: Sendable, Hashable, Codable {
    public let volumeMultiplier: Double
    public let rpeCap: Double
    public let targetRPE: Double

    public init(volumeMultiplier: Double, rpeCap: Double, targetRPE: Double) {
        self.volumeMultiplier = volumeMultiplier
        self.rpeCap = rpeCap
        self.targetRPE = targetRPE
    }
}

public enum ReadinessGating {
    public static func effect(for readiness: ReadinessScore?) -> ReadinessGatingEffect {
        guard let readiness else {
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 8.5, targetRPE: 8.0)
        }
        switch readiness.band {
        case .depleted:
            return ReadinessGatingEffect(volumeMultiplier: 0.7, rpeCap: 7.0, targetRPE: 6.5)
        case .balanced:
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 8.5, targetRPE: 8.0)
        case .primed:
            return ReadinessGatingEffect(volumeMultiplier: 1.0, rpeCap: 10.0, targetRPE: 9.0)
        }
    }
}
