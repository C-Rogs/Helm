import Foundation
import Persistence

enum ChatBootstrap {
    private static let persistence = PersistenceBootstrap.persistenceStore

    @MainActor
    static let controller = ChatController(persistence: persistence)

    @MainActor
    static func start() {
        Task {
            await controller.onAppear()
        }
    }
}
