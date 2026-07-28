import Core
import Foundation

public enum CoachArchetypeLibraryError: Error, Sendable, Equatable {
    case resourceMissing
    case decodeFailed
}

/// Loads the bundled coach archetype catalog from the app exercise seed resources.
public enum CoachArchetypeLibrary: Sendable {
    public static let resourceName = "coach_archetype_catalog"
    public static let resourceSubdirectory = "ExerciseSeed"

    public static func load(from data: Data) throws -> CoachArchetypeCatalog {
        do {
            return try JSONDecoder().decode(CoachArchetypeCatalog.self, from: data)
        } catch {
            throw CoachArchetypeLibraryError.decodeFailed
        }
    }

    public static func load(from url: URL) throws -> CoachArchetypeCatalog {
        try load(from: Data(contentsOf: url))
    }

    public static func bundled(in bundle: Bundle = .main) throws -> CoachArchetypeCatalog {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CoachArchetypeLibraryError.resourceMissing
        }
        return try load(from: url)
    }
}
