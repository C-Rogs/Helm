import Core
import Foundation
import HealthKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Ingest metadata persistence")
struct IngestMetadataStoreTests {
    @Test("metadata survives new HealthKitIngest actor instance")
    func metadataRoundTrip() async throws {
        let store = try PersistenceStore.inMemory()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let mockStore = MockHealthKitStoreClient()

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        try await ingest.requestAuthorization()
        _ = await ingest.syncNow()

        var status = await ingest.currentStatus()
        #expect(status.authorizationRequested)

        let relaunched = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        status = await relaunched.currentStatus()
        #expect(status.authorizationRequested)
        #expect(status.lastSyncFinishedAt != nil)
    }

    @Test("shouldBootstrapOnLaunch when authorization was previously requested")
    func bootstrapAfterAuth() async throws {
        let store = try PersistenceStore.inMemory()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let mockStore = MockHealthKitStoreClient()
        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        try await ingest.requestAuthorization()

        let relaunched = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        #expect(await relaunched.shouldBootstrapOnLaunch(backfillComplete: false))
    }

    @Test("startObserving runs when bootstrap path executes")
    func bootstrapStartsObservers() async throws {
        let store = try PersistenceStore.inMemory()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let mockStore = MockHealthKitStoreClient()
        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        try await ingest.requestAuthorization()

        let relaunched = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        guard await relaunched.shouldBootstrapOnLaunch(backfillComplete: false) else {
            Issue.record("Expected bootstrap eligibility after authorization")
            return
        }

        await relaunched.startObserving()
        let status = await relaunched.currentStatus()
        #expect(status.isObserving)
    }
}
