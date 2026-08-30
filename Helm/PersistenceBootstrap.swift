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
        do {
            let result = try await store.importBundledExerciseSeedIfNeeded()
            if result.skippedBecauseUpToDate {
                logger.info("Exercise seed already applied version=\(result.appliedSeedVersion)")
            } else {
                logger.info("Exercise seed import complete count=\(result.importedCount) version=\(result.appliedSeedVersion)")
            }
        } catch {
            logger.error("Exercise seed import failed: \(String(describing: error))")
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
