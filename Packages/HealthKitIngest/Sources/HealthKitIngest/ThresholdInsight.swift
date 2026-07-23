import Foundation
import ReadinessKit

public enum ThresholdCrossingDirection: String, Sendable, Equatable, Codable {
    case above
    case below
}

public struct ThresholdInsight: Sendable, Equatable, Identifiable {
    public let id: String
    public let metricLabel: String
    public let message: String
    public let direction: ThresholdCrossingDirection

    public init(
        id: String,
        metricLabel: String,
        message: String,
        direction: ThresholdCrossingDirection
    ) {
        self.id = id
        self.metricLabel = metricLabel
        self.message = message
        self.direction = direction
    }
}

public enum ThresholdInsightEngine {
    public static let threshold = 0.75

    private struct Contributor: Sendable {
        let id: String
        let label: String
        let z: Double?
    }

    public static func detect(
        previous: ReadinessScore?,
        current: ReadinessScore
    ) -> ThresholdInsight? {
        guard let previous else { return nil }

        let previousContributors = contributors(from: previous)
        let currentContributors = contributors(from: current)

        var best: (insight: ThresholdInsight, magnitude: Double)?

        for currentContributor in currentContributors {
            guard let currentZ = currentContributor.z else { continue }
            let previousZ = previousContributors.first(where: { $0.id == currentContributor.id })?.z
            guard let previousZ else { continue }

            let previousInside = abs(previousZ) <= threshold
            let currentOutside = abs(currentZ) > threshold
            guard previousInside && currentOutside else { continue }

            let direction: ThresholdCrossingDirection = currentZ > 0 ? .above : .below
            let detail = direction == .above ? "above baseline" : "below baseline"
            let insight = ThresholdInsight(
                id: "\(currentContributor.id)_\(direction.rawValue)",
                metricLabel: currentContributor.label,
                message: "\(currentContributor.label) moved \(detail) (z \(formattedZ(currentZ))).",
                direction: direction
            )
            let magnitude = abs(currentZ)
            if best == nil || magnitude > (best?.magnitude ?? 0) {
                best = (insight, magnitude)
            }
        }

        return best?.insight
    }

    private static func contributors(from score: ReadinessScore) -> [Contributor] {
        var items: [Contributor] = [
            Contributor(id: "hrv", label: "HRV", z: score.contributors.zHRV),
            Contributor(id: "rhr", label: "Resting HR", z: score.contributors.zRestingHR),
            Contributor(id: "sleep", label: "Sleep", z: score.contributors.zSleep)
        ]

        if score.contributors.zStrain != nil {
            items.append(Contributor(id: "strain", label: "Strain", z: score.contributors.zStrain))
        }
        if score.contributors.zRespiratory != nil {
            items.append(Contributor(id: "respiratory", label: "Respiratory", z: score.contributors.zRespiratory))
        }
        if score.contributors.zTemperature != nil {
            items.append(Contributor(id: "temperature", label: "Temperature", z: score.contributors.zTemperature))
        }

        return items
    }

    private static func formattedZ(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value))"
    }
}
