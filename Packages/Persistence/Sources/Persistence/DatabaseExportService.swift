import Foundation

public struct DatabaseExportService: Sendable {
    public init() {}

    public func exportCheckpointedCopy(from store: PersistenceStore) async throws -> URL {
        try await store.exportCheckpointedCopy()
    }
}
