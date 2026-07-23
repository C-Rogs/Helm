import Core
import Foundation

/// One logical day's grounded context, serialized by the caller.
public struct CoachContextDay: Sendable, Hashable, Codable, Equatable {
    public let helmDay: HelmDay
    public let text: String

    public init(helmDay: HelmDay, text: String) {
        self.helmDay = helmDay
        self.text = text
    }
}

/// Recent health and training context passed into the builder.
public struct CoachContextDays: Sendable, Hashable, Codable, Equatable {
    public let readinessBaselines: String
    public let evidence: [EvidenceRecord]
    public let recent: [CoachContextDay]

    public init(
        readinessBaselines: String = "",
        evidence: [EvidenceRecord] = [],
        recent: [CoachContextDay] = []
    ) {
        self.readinessBaselines = readinessBaselines
        self.evidence = evidence
        self.recent = recent
    }

    public static let empty = CoachContextDays()
}
