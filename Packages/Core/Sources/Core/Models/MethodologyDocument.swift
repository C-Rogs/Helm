import Foundation

/// Bundled methodology library entry for the Sources screen and coach evidence index.
public struct MethodologyDocument: Sendable, Hashable, Codable, Equatable {
    public let seedVersion: Int
    public let placeholder: Bool
    public let modules: [ResourceModule]
    public let evidence: [EvidenceRecord]
    public let topics: [MethodologyTopic]

    public init(
        seedVersion: Int,
        placeholder: Bool,
        modules: [ResourceModule] = [],
        evidence: [EvidenceRecord] = [],
        topics: [MethodologyTopic] = []
    ) {
        self.seedVersion = seedVersion
        self.placeholder = placeholder
        self.modules = modules
        self.evidence = evidence
        self.topics = topics
    }

    public static let empty = MethodologyDocument(seedVersion: 0, placeholder: true)

    public func evidence(for ids: [String]) -> [EvidenceRecord] {
        let lookup = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }
}

public struct MethodologyTopic: Sendable, Hashable, Codable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let citationIDs: [String]

    public init(id: String, title: String, body: String, citationIDs: [String] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.citationIDs = citationIDs
    }
}
