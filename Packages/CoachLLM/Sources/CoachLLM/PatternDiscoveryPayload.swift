import Foundation

/// Schema-only hypothesis proposals. Engines compile and test; the model never ships numbers.
public struct PatternDiscoveryPayload: Sendable, Hashable, Codable, Equatable {
    public let schemaVersion: String
    public let hypotheses: [PatternDiscoveryHypothesis]

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.patternDiscoveryV1.rawValue,
        hypotheses: [PatternDiscoveryHypothesis]
    ) {
        self.schemaVersion = schemaVersion
        self.hypotheses = hypotheses
    }
}

public struct PatternDiscoveryHypothesis: Sendable, Hashable, Codable, Equatable {
    public let id: String
    public let exposureField: String
    public let exposureOp: String
    public let exposureBand: String?
    public let outcomeField: String
    public let lag: Int
    public let requireTrainingDay: Bool

    public init(
        id: String,
        exposureField: String,
        exposureOp: String,
        exposureBand: String? = nil,
        outcomeField: String,
        lag: Int,
        requireTrainingDay: Bool = false
    ) {
        self.id = id
        self.exposureField = exposureField
        self.exposureOp = exposureOp
        self.exposureBand = exposureBand
        self.outcomeField = outcomeField
        self.lag = lag
        self.requireTrainingDay = requireTrainingDay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        exposureField = try container.decode(String.self, forKey: .exposureField)
        exposureOp = try container.decode(String.self, forKey: .exposureOp)
        exposureBand = try container.decodeIfPresent(String.self, forKey: .exposureBand)
        outcomeField = try container.decode(String.self, forKey: .outcomeField)
        lag = try container.decodeIfPresent(Int.self, forKey: .lag) ?? 0
        requireTrainingDay = try container.decodeIfPresent(Bool.self, forKey: .requireTrainingDay) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case exposureField
        case exposureOp
        case exposureBand
        case outcomeField
        case lag
        case requireTrainingDay
    }
}
