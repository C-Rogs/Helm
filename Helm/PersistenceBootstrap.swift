import Diagnostics
import Foundation
import Persistence

enum PersistenceBootstrap {
    private static let store: PersistenceStore = {
        do {
            return try PersistenceStore.openDefault()
        } catch {
            fatalError("Failed to open persistence store: \(error)")
        }
    }()

    static var persistenceStore: PersistenceStore { store }

    static var schemaVersion: Int {
        store.schemaVersion
    }

    static var exerciseSeedVersion: Int {
        (try? store.exerciseSeedVersion()) ?? 0
    }

    static func importExerciseSeed() async {
        let logger = helmLogger(category: .persistence)
        guard let manifestURL = bundledJSON(named: "exercises") else {
            logger.error("Exercise seed import failed: exercises.json is missing from the app bundle.")
            return
        }
        let catalogURL = bundledJSON(named: "free-exercise-db")
        if catalogURL == nil {
            logger.error("Exercise catalog free-exercise-db.json missing; importing overlay only.")
        }

        do {
            let result = try await store.importExerciseSeedIfNeeded(
                manifestURL: manifestURL,
                catalogURL: catalogURL
            )
            if !result.skippedBecauseUpToDate {
                logger.info("Exercise seed import complete count=\(result.importedCount) version=\(result.appliedSeedVersion)")
            }
        } catch {
            logger.error("Exercise seed import failed: \(error.localizedDescription)")
        }
    }

    private static func bundledJSON(named name: String) -> URL? {
        let fileName = "\(name).json"
        let directCandidates = [
            Bundle.main.bundleURL.appendingPathComponent("ExerciseSeed").appendingPathComponent(fileName),
            Bundle.main.bundleURL.appendingPathComponent(fileName)
        ]
        for url in directCandidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let subdirectories = ["ExerciseSeed", "Helm/Resources/ExerciseSeed", "Resources/ExerciseSeed"]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory) {
                return url
            }
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            return url
        }
        if let enumerator = FileManager.default.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.lastPathComponent == fileName {
                return url
            }
        }
        return nil
    }

    static func logOpen() async {
        let logger = helmLogger(category: .persistence)
        logger.info("Persistence store opened")

        await DiagnosticsLog.shared.record(
            category: .persistence,
            level: .info,
            message: "Persistence store opened",
            context: [
                "schemaVersion": String(store.schemaVersion),
                "iCloudBackup": "excluded"
            ]
        )
    }
}
