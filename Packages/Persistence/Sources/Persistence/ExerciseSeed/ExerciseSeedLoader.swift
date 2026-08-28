import Foundation

public enum ExerciseSeedLoader {
    public enum LoaderError: Error, Equatable, LocalizedError {
        case missingManifest
        case missingCatalog(resource: String)
        case invalidManifest(String)

        public var errorDescription: String? {
            switch self {
            case .missingManifest:
                "Exercise seed manifest is missing from the app bundle."
            case let .missingCatalog(resource):
                "Exercise catalog \(resource).json is missing from the app bundle."
            case let .invalidManifest(detail):
                "Exercise seed manifest is invalid (\(detail))."
            }
        }
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
        manifestDirectory: URL,
        catalogURL: URL? = nil
    ) throws -> ResolvedExerciseSeed {
        let catalogEntries: [ExerciseSeedEntry]
        if let resource = manifest.catalogResource {
            let resolvedCatalogURL = catalogURL ?? manifestDirectory
                .appendingPathComponent(resource)
                .appendingPathExtension("json")
            guard FileManager.default.fileExists(atPath: resolvedCatalogURL.path) else {
                throw LoaderError.missingCatalog(resource: resource)
            }
            let data = try Data(contentsOf: resolvedCatalogURL)
            let records = try FreeExerciseCatalogSupport.decodeCatalog(from: data)
            catalogEntries = ExerciseSeedCatalogMapper.mapCatalogRecords(records)
        } else {
            catalogEntries = []
        }

        let overlay = manifest.exercises
        let curation = manifest.pickerCuration ?? (overlay.isEmpty ? .algorithmic : .explicit)

        if overlay.isEmpty {
            return ResolvedExerciseSeed(
                entries: catalogEntries,
                pickerCuration: curation,
                explicitPickerIDs: []
            )
        }

        if catalogEntries.isEmpty {
            let explicitIDs = Set(overlay.filter { $0.isPickerDefault == true }.map(\.id))
            return ResolvedExerciseSeed(
                entries: overlay,
                pickerCuration: curation,
                explicitPickerIDs: explicitIDs
            )
        }

        let merged = ExerciseSeedMerger.merge(catalog: catalogEntries, overlay: overlay)
        return ResolvedExerciseSeed(
            entries: merged.entries,
            pickerCuration: curation,
            explicitPickerIDs: merged.explicitPickerIDs
        )
    }
}
