import Foundation
import Persistence

enum TrendsBootstrap {
    @MainActor
    static let controller = TrendsController(persistence: PersistenceBootstrap.persistenceStore)

    @MainActor
    static func start() {
        controller.refresh()
    }
}
