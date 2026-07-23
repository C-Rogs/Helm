import Foundation

public enum ExerciseSeedLoader {
    public enum LoaderError: Error, Equatable {
        case missingManifest
        case missingCatalog(resource: String)
        case invalidManifest(String)
    }

    public static func loadManifest(from url: URL) throws -> ExerciseSeedDocument {
        let data = try Data(contentsOf: url)
        return try loadManifest(from: data)
    }

    public static func loadManifest(from data: Data) throws -> ExerciseSeedDocument {
        do {
            return try JSONDecoder().decode(ExerciseSeedDocument.self, from: data)
        } catch {
            throw LoaderError.invalidManifest(error.localizedDescription)
        }
    }

    public static func resolveEntries(
        manifest: ExerciseSeedDocument,
        manifestDirectory: URL
    ) throws -> [ExerciseSeedEntry] {
        if let resource = manifest.catalogResource {
            let catalogURL = manifestDirectory
                .appendingPathComponent(resource)
                .appendingPathExtension("json")
            guard FileManager.default.fileExists(atPath: catalogURL.path) else {
                throw LoaderError.missingCatalog(resource: resource)
            }
            let data = try Data(contentsOf: catalogURL)
            let records = try FreeExerciseCatalogSupport.decodeCatalog(from: data)
            return ExerciseSeedCatalogMapper.mapCatalogRecords(records)
        }
        return manifest.exercises
    }
}
