import Foundation

/// An individual refinement proposed by the coach after observing a
/// conversation session.
public struct MemoryRefinementEntry: Sendable, Hashable, Codable, Equatable {
    /// MemoryProfile field name (preferences, whatHasWorked, etc.).
    public var field: String
    /// How to apply the change.
    public var action: RefinementAction
    /// Suggested new or merged text for the field.
    public var proposedValue: String
    /// How confident the coach is in this observation.
    public var confidence: RefinementConfidence
    /// Source evidence snippets from the conversation that support the proposal.
    public var evidence: [RefinementEvidence]
    /// Why the coach believes this update is warranted.
    public var rationale: String

    public init(
        field: String,
        action: RefinementAction,
        proposedValue: String,
        confidence: RefinementConfidence,
        evidence: [RefinementEvidence],
        rationale: String
    ) {
        self.field = field
        self.action = action
        self.proposedValue = proposedValue
        self.confidence = confidence
        self.evidence = evidence
        self.rationale = rationale
    }

    public enum RefinementAction: String, Sendable, Hashable, Codable {
        case add
        case merge
        case replace
        case remove
    }

    public enum RefinementConfidence: String, Sendable, Hashable, Codable {
        case low
        case medium
        case high
    }

    public struct RefinementEvidence: Sendable, Hashable, Codable, Equatable {
        public var sessionDate: String
        public var excerpt: String

        public init(sessionDate: String, excerpt: String) {
            self.sessionDate = sessionDate
            self.excerpt = excerpt
        }
    }
}

/// The top-level memory_refinement.v1 payload that the coach emits.
public struct MemoryRefinementPayload: Sendable, Hashable, Codable, Equatable {
    public var schemaVersion: String
    /// Short coach-facing summary of what was learned.
    public var reply: String
    /// One or more memory field refinements.
    public var refinements: [MemoryRefinementEntry]

    public init(
        schemaVersion: String = "memory_refinement.v1",
        reply: String,
        refinements: [MemoryRefinementEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.refinements = refinements
    }
}
