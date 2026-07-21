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

    static func logOpen() async {
        let logger = helmLogger(category: .persistence)
        logger.info("Persistence store opened")

        await DiagnosticsLog.shared.record(
            category: .persistence,
            level: .info,
            message: "Persistence store opened",
            context: [
                "schemaVersion": String(store.schemaVersion),
                "iCloudBackup": "included"
            ]
        )
    }
}
