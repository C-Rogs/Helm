import Foundation
import GRDB

enum DatabaseFactory {
    static func makePool(at url: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try DatabasePool(path: url.path, configuration: configuration)
    }

    static func makeInMemoryPool() throws -> DatabasePool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-test-\(UUID().uuidString).sqlite")
        return try makePool(at: url)
    }
}
