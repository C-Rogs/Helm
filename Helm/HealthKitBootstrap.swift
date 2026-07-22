import Foundation
import HealthKitIngest
import Persistence

enum HealthKitBootstrap {
    private static let ingest: HealthKitIngest = {
        let anchorDirectory: URL
        do {
            anchorDirectory = try DatabaseLocation.defaultDatabaseURL().deletingLastPathComponent()
        } catch {
            fatalError("Failed to resolve HealthKit anchor directory: \(error)")
        }
        return HealthKitIngest(
            persistence: PersistenceBootstrap.persistenceStore,
            anchorDirectoryURL: anchorDirectory
        )
    }()

    static var healthKitIngest: HealthKitIngest { ingest }
}
