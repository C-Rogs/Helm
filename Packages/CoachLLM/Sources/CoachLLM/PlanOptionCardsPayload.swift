import Foundation

/// LLM-written presentation copy for one candidate plan card.
public struct PlanOptionCardCopy: Codable, Sendable, Equatable {
    public let candidateID: String
    /// One-line outcome summary, e.g. "Fastest strength gains per session".
    public let outcome: String
    public let benefits: [String]
    public let challenges: [String]
    /// Optional source titles from search grounding.
    public let sources: [String]

    public init(
        candidateID: String,
        outcome: String,
        benefits: [String],
        challenges: [String],
        sources: [String] = []
    ) {
        self.candidateID = candidateID
        self.outcome = outcome
        self.benefits = benefits
        self.challenges = challenges
        self.sources = sources
    }

    enum CodingKeys: String, CodingKey {
        case candidateID
        case outcome
        case benefits
        case challenges
        case sources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateID = try container.decode(String.self, forKey: .candidateID)
        outcome = try container.decode(String.self, forKey: .outcome)
        benefits = try container.decodeIfPresent([String].self, forKey: .benefits) ?? []
        challenges = try container.decodeIfPresent([String].self, forKey: .challenges) ?? []
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
    }
}

/// Top-level structured payload for the plan option cards call.
public struct PlanOptionCardsPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let cards: [PlanOptionCardCopy]

    public init(schemaVersion: String, cards: [PlanOptionCardCopy]) {
        self.schemaVersion = schemaVersion
        self.cards = cards
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case cards
    }
}
