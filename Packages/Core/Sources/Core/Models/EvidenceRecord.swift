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

    enum CodingKeys: String, CodingKey {
        case id, title, summary, citation, url, placeholder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        citation = Self.decodeCitation(from: container)
        url = Self.decodeURL(from: container)
        placeholder = try container.decodeIfPresent(Bool.self, forKey: .placeholder) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(citation, forKey: .citation)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(placeholder, forKey: .placeholder)
    }

    private struct CitationObject: Decodable {
        let source: String?
        let line: String?
    }

    private static func decodeCitation(from container: KeyedDecodingContainer<CodingKeys>) -> String {
        if let text = try? container.decode(String.self, forKey: .citation) {
            return text
        }
        guard let object = try? container.decode(CitationObject.self, forKey: .citation) else {
            return ""
        }
        return [object.source, object.line]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    private static func decodeURL(from container: KeyedDecodingContainer<CodingKeys>) -> URL? {
        guard container.contains(.url) else { return nil }
        if (try? container.decodeNil(forKey: .url)) == true {
            return nil
        }
        if let text = try? container.decode(String.self, forKey: .url) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : URL(string: trimmed)
        }
        return try? container.decode(URL.self, forKey: .url)
    }
}
