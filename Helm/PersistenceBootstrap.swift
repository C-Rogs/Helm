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
        guard let manifestURL = Bundle.main.url(
            forResource: "exercises",
            withExtension: "json",
            subdirectory: "ExerciseSeed"
        ) ?? Bundle.main.url(forResource: "exercises", withExtension: "json")
        else {
            return
        }

        do {
            let result = try await store.importExerciseSeedIfNeeded(manifestURL: manifestURL)
            if !result.skippedBecauseUpToDate {
                let logger = helmLogger(category: .persistence)
                logger.info("Exercise seed import complete count=\(result.importedCount) version=\(result.appliedSeedVersion)")
            }
        } catch {
            let logger = helmLogger(category: .persistence)
            logger.error("Exercise seed import failed: \(error.localizedDescription)")
        }
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
