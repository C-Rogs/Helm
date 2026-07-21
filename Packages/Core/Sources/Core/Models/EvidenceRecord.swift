import Foundation

public struct EvidenceRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let citation: String
    public let url: URL?
    public let placeholder: Bool

    public init(
        id: String,
        title: String,
        summary: String,
        citation: String,
        url: URL? = nil,
        placeholder: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.citation = citation
        self.url = url
        self.placeholder = placeholder
    }
}
