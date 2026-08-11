import Core
import Foundation

/// Validation map built once per turn from the evidence index sent in context.
/// Provides O(1) lookup for each cited tag type.
public struct CitationValidationMap: Sendable, Equatable {
    public let evidenceIDs: Set<String>
    public let topicIDs: Set<String>

    public init(
        evidenceRecords: [EvidenceRecord],
        topics: [MethodologyTopic]
    ) {
        evidenceIDs = Set(evidenceRecords.map(\.id))
        topicIDs = Set(topics.map { "topic:\($0.id)" })
    }

    /// Convenience init when only evidence is available (topic validation disabled).
    public init(evidenceRecords: [EvidenceRecord]) {
        self.evidenceIDs = Set(evidenceRecords.map(\.id))
        self.topicIDs = []
    }

    /// Returns true when the cited ID was present in the evidence index sent this turn.
    public func isValidEvidence(_ id: String) -> Bool {
        evidenceIDs.contains(id)
    }

    public func isValidTopic(_ fullID: String) -> Bool {
        topicIDs.contains(fullID)
    }

    public func isValidEngine(_ anchor: String) -> Bool {
        EngineAnchor.allRawValues.contains(anchor)
    }
}

// MARK: - Diagnostics

public enum CitationFailureType: String, Sendable {
    case phantomEvidence
    case unknownTopic
    case unknownEngine
    case malformedTag
}
