import Foundation

/// Display-only copy and presentation for resting heart rate on Recovery surfaces.
public enum RestingHeartRateDisplay {
    public static let sourceSubtitle = "from Apple Health"

    public static let settingsHealthExplanation =
        "Resting heart rate on Recovery comes from HealthKit overnight samples, not live Apple Watch heart rate during workouts."

    public struct ContributorPresentation: Sendable, Equatable {
        public let subtitle: String?
        public let isValueMuted: Bool

        public init(subtitle: String?, isValueMuted: Bool) {
            self.subtitle = subtitle
            self.isValueMuted = isValueMuted
        }
    }

    public static func contributorPresentation(
        hasValue: Bool,
        isStale: Bool
    ) -> ContributorPresentation {
        ContributorPresentation(
            subtitle: hasValue ? sourceSubtitle : nil,
            isValueMuted: isStale
        )
    }
}
