import Core
import Foundation

public enum MethodologyLibraryError: Error, Sendable, Equatable {
    case resourceMissing
    case decodeFailed
}

/// Loads the bundled methodology seed used by Sources and the coach evidence index.
public enum MethodologyLibrary: Sendable {
    public static let resourceName = "methodology"
    public static let resourceSubdirectory = "MethodologySeed"

    public static func load(from data: Data) throws -> MethodologyDocument {
        do {
            return try JSONDecoder().decode(MethodologyDocument.self, from: data)
        } catch {
            throw MethodologyLibraryError.decodeFailed
        }
    }

    public static func load(from url: URL) throws -> MethodologyDocument {
        try load(from: Data(contentsOf: url))
    }

    public static func bundled(in bundle: Bundle = .main) throws -> MethodologyDocument {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "json") else {
            throw MethodologyLibraryError.resourceMissing
        }
        return try load(from: url)
    }

    public static func evidenceLookup(from document: MethodologyDocument) -> [String: EvidenceRecord] {
        Dictionary(uniqueKeysWithValues: document.evidence.map { ($0.id, $0) })
    }
}
