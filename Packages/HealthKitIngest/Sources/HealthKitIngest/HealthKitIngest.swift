import Diagnostics
import Foundation
import HealthKit
import OSLog
import Persistence

public actor HealthKitIngest {
    public static let defaultOwnBundleID = "com.cameronro.helm"

    private let store: any HealthKitStoreClient
    private let persistence: PersistenceStore
    private let anchorStore: HealthKitAnchorStore
    private var metadataStore: IngestMetadataStore
    private let writer: IngestPersistenceWriter
    private let ownBundleID: String
    private let diagnosticsLog: DiagnosticsLog
    private let signpost: HelmSignpost
    private let log: Logger

    private var isObserving = false
    private var authorizationRequested = false
    private var lastSyncFinishedAt: Date?
    private var lastSyncSampleCount = 0
    private var lastSyncDeletedCount = 0
    private var lastErrorMessage: String?

    private var observerQueries: [HealthKitSampleKind: HKQuery] = [:]
    private var pendingKinds: Set<HealthKitSampleKind> = []
    private var syncTask: Task<Void, Never>?
    private var familyContinuations: [HealthKitMetricFamily: [UUID: AsyncStream<HealthKitMetricSnapshot>.Continuation]] = [:]

    public init(
        persistence: PersistenceStore,
        anchorDirectoryURL: URL,
        ownBundleID: String = defaultOwnBundleID,
        store: any HealthKitStoreClient = LiveHealthKitStore(),
        diagnosticsLog: DiagnosticsLog = .shared
    ) {
        self.persistence = persistence
        anchorStore = HealthKitAnchorStore(directoryURL: anchorDirectoryURL)
        metadataStore = IngestMetadataStore(directoryURL: anchorDirectoryURL)
        writer = IngestPersistenceWriter(store: persistence)
        self.ownBundleID = ownBundleID
        self.store = store
        self.diagnosticsLog = diagnosticsLog
        signpost = HelmSignpost(name: .healthKitObserverFetch, category: .healthKitIngest)
        log = helmLogger(category: .healthKitIngest)

        let saved = metadataStore.current
        authorizationRequested = saved.authorizationRequested
        lastSyncFinishedAt = saved.lastSyncFinishedAt
        lastSyncSampleCount = saved.lastSyncSampleCount
        lastSyncDeletedCount = saved.lastSyncDeletedCount
    }

    public func shouldBootstrapOnLaunch(backfillComplete: Bool) async -> Bool {
        if authorizationRequested { return true }
        if await anchorStore.hasPersistedAnchors { return true }
        return backfillComplete
    }

    public func currentStatus() -> HealthKitIngestStatus {
        HealthKitIngestStatus(
            isObserving: isObserving,
            lastSyncFinishedAt: lastSyncFinishedAt,
            lastSyncSampleCount: lastSyncSampleCount,
            lastSyncDeletedCount: lastSyncDeletedCount,
            authorizationRequested: authorizationRequested,
            lastErrorMessage: lastErrorMessage
        )
    }

    public func snapshot(for family: HealthKitMetricFamily) -> HealthKitMetricSnapshot {
        HealthKitMetricSnapshot(
            family: family,
            capturedAt: Date(),
            status: currentStatus()
        )
    }

    public nonisolated func updates(for family: HealthKitMetricFamily) -> AsyncStream<HealthKitMetricSnapshot> {
        AsyncStream { continuation in
            let token = UUID()
            Task {
                await self.registerContinuation(continuation, token: token, for: family)
                continuation.yield(await self.snapshot(for: family))
            }
            continuation.onTermination = { @Sendable _ in
                Task { await self.unregisterContinuation(token: token, for: family) }
            }
        }
    }

    public func requestAuthorization() async throws {
        guard store.isHealthDataAvailable() else {
            throw HealthKitIngestError.healthDataUnavailable
        }

        try await store.requestAuthorization(
            toShare: HealthKitSampleKind.shareTypes,
            read: HealthKitSampleKind.readTypes
        )
        authorizationRequested = true
        try persistMetadata()
        log.info("HealthKit authorization requested")
    }

    public func startObserving() async {
        guard store.isHealthDataAvailable() else {
            lastErrorMessage = HealthKitIngestError.healthDataUnavailable.localizedDescription
            return
        }

        for kind in HealthKitSampleKind.allCases {
            do {
                try await store.enableBackgroundDelivery(
                    for: kind.sampleType,
                    frequency: kind.backgroundDeliveryFrequency
                )
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Background delivery failed",
                    context: ["sampleType": kind.rawValue]
                )
                lastErrorMessage = error.localizedDescription
            }

            if observerQueries[kind] == nil {
                let query = store.startObserver(for: kind.sampleType) { [ingest = self, kind] in
                    Task { await ingest.scheduleSync(for: kind) }
                }
                observerQueries[kind] = query
            }
        }

        isObserving = true
        log.info("HealthKit observers started for \(HealthKitSampleKind.allCases.count) sample types")
    }

    public func stopObserving() async {
        for (kind, query) in observerQueries {
            store.stop(query)
            do {
                try await store.disableBackgroundDelivery(for: kind.sampleType)
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Disable background delivery failed",
                    context: ["sampleType": kind.rawValue]
                )
            }
        }
        observerQueries.removeAll()
        isObserving = false
        log.info("HealthKit observers stopped, background delivery disabled")
    }

    public func syncNow() async -> HealthKitIngestOutcome {
        guard store.isHealthDataAvailable() else {
            lastErrorMessage = HealthKitIngestError.healthDataUnavailable.localizedDescription
            return .empty
        }

        var totalIngested = 0
        var totalDeleted = 0
        var affectedFamilies: Set<HealthKitMetricFamily> = []

        for kind in HealthKitSampleKind.allCases {
            let outcome = await syncKind(kind)
            totalIngested += outcome.samplesIngested
            totalDeleted += outcome.samplesDeleted
            affectedFamilies.formUnion(outcome.affectedFamilies)
        }

        lastSyncFinishedAt = Date()
        lastSyncSampleCount = totalIngested
        lastSyncDeletedCount = totalDeleted
        lastErrorMessage = nil
        try? persistMetadata()

        publishSnapshots(for: affectedFamilies)

        return HealthKitIngestOutcome(
            samplesIngested: totalIngested,
            samplesDeleted: totalDeleted,
            affectedFamilies: affectedFamilies
        )
    }

    public func resetAnchors() async throws {
        try await anchorStore.resetAll()
        log.info("HealthKit ingest anchors reset")
    }

    private func scheduleSync(for kind: HealthKitSampleKind) {
        guard isObserving else { return }
        pendingKinds.insert(kind)
        guard syncTask == nil else { return }

        syncTask = Task {
            await self.drainPendingSync()
            self.completeSyncTaskIfNeeded()
        }
    }

    private func completeSyncTaskIfNeeded() {
        syncTask = nil
        if !pendingKinds.isEmpty, let kind = pendingKinds.first {
            scheduleSync(for: kind)
        }
    }

    private func drainPendingSync() async {
        while !pendingKinds.isEmpty {
            let batch = pendingKinds
            pendingKinds = []

            var totalIngested = 0
            var totalDeleted = 0
            var affectedFamilies: Set<HealthKitMetricFamily> = []

            for kind in batch.sorted(by: { $0.rawValue < $1.rawValue }) {
                let outcome = await syncKind(kind)
                totalIngested += outcome.samplesIngested
                totalDeleted += outcome.samplesDeleted
                affectedFamilies.formUnion(outcome.affectedFamilies)
            }

            lastSyncFinishedAt = Date()
            lastSyncSampleCount = totalIngested
            lastSyncDeletedCount = totalDeleted
            try? persistMetadata()
            publishSnapshots(for: affectedFamilies)
        }
    }

    private func syncKind(_ kind: HealthKitSampleKind) async -> HealthKitIngestOutcome {
        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)

        defer {
            signpost.end(id: signpostID)
        }

        do {
            let anchor = await anchorStore.anchor(for: kind)
            let fetchResult = try await store.fetchAnchored(
                sampleType: kind.sampleType,
                anchor: anchor
            )

            var delta = IngestSampleMapper.delta(
                kind: kind,
                addedSamples: fetchResult.addedSamples,
                deletedObjectIDs: fetchResult.deletedObjectIDs,
                ownBundleID: ownBundleID
            )

            if kind == .workout, !delta.addedWorkouts.isEmpty {
                let ingester = WorkoutTRIMPIngester(store: store, persistence: persistence)
                let trimpByTargetDay = try await ingester.trimpByTargetDay(for: delta.addedWorkouts)
                delta = IngestDelta(
                    kind: delta.kind,
                    addedQuantitySamples: delta.addedQuantitySamples,
                    addedSleepSamples: delta.addedSleepSamples,
                    addedWorkouts: delta.addedWorkouts,
                    deletedSampleIDs: delta.deletedSampleIDs,
                    trimpByTargetDay: trimpByTargetDay
                )
            }

            let sampleCount = delta.addedQuantitySamples.count
                + delta.addedSleepSamples.count
                + delta.addedWorkouts.count
            let deletedCount = delta.deletedSampleIDs.count

            let families = try writer.apply(delta: delta)

            if let newAnchor = fetchResult.newAnchor {
                try await anchorStore.save(anchor: newAnchor, for: kind)
            }

            if sampleCount > 0 || deletedCount > 0 {
                log.info(
                    "Ingested \(sampleCount) samples, \(deletedCount) deletions for \(kind.rawValue, privacy: .public)"
                )
            }

            return HealthKitIngestOutcome(
                samplesIngested: sampleCount,
                samplesDeleted: deletedCount,
                affectedFamilies: families
            )
        } catch {
            await diagnosticsLog.capture(
                error: error,
                category: .healthKitIngest,
                message: "HealthKit sync failed",
                context: ["sampleType": kind.rawValue]
            )
            lastErrorMessage = error.localizedDescription
            return .empty
        }
    }

    private func publishSnapshots(for families: Set<HealthKitMetricFamily>) {
        guard !families.isEmpty else { return }
        let status = currentStatus()
        let capturedAt = Date()

        for family in families {
            let snapshot = HealthKitMetricSnapshot(
                family: family,
                capturedAt: capturedAt,
                status: status
            )
            for continuation in familyContinuations[family, default: [:]].values {
                continuation.yield(snapshot)
            }
        }
    }

    private func registerContinuation(
        _ continuation: AsyncStream<HealthKitMetricSnapshot>.Continuation,
        token: UUID,
        for family: HealthKitMetricFamily
    ) {
        familyContinuations[family, default: [:]][token] = continuation
    }

    private func unregisterContinuation(token: UUID, for family: HealthKitMetricFamily) {
        familyContinuations[family]?.removeValue(forKey: token)
        if familyContinuations[family]?.isEmpty == true {
            familyContinuations.removeValue(forKey: family)
        }
    }

    private func persistMetadata() throws {
        try metadataStore.save(
            IngestMetadata(
                authorizationRequested: authorizationRequested,
                lastSyncFinishedAt: lastSyncFinishedAt,
                lastSyncSampleCount: lastSyncSampleCount,
                lastSyncDeletedCount: lastSyncDeletedCount
            )
        )
    }
}
