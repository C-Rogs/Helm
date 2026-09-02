import Diagnostics
import Foundation
import HealthKit
import OSLog
import Persistence
import Core

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
    private var didResetBodyFatAnchorThisProcess = false
    private var lastBodyFatTrace = BodyFatQueryTrace.empty
    private var lastBodyFatFacts = BodyFatLatestFacts.empty

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
        await syncKinds(Array(HealthKitSampleKind.allCases))
    }

    public func syncKinds(_ kinds: [HealthKitSampleKind]) async -> HealthKitIngestOutcome {
        guard store.isHealthDataAvailable() else {
            lastErrorMessage = HealthKitIngestError.healthDataUnavailable.localizedDescription
            return .empty
        }

        var totalIngested = 0
        var totalDeleted = 0
        var affectedFamilies: Set<HealthKitMetricFamily> = []

        for kind in kinds {
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

    public func resetAnchor(for kind: HealthKitSampleKind) async throws {
        try await anchorStore.resetAnchor(for: kind)
        log.info("HealthKit anchor reset for \(kind.rawValue, privacy: .public)")
    }

    public func lastBodyFatQueryTrace() -> BodyFatQueryTrace {
        lastBodyFatTrace
    }

    public func lastBodyFatLatestFacts() -> BodyFatLatestFacts {
        lastBodyFatFacts
    }

    /// Newest Body Fat Percentage samples HealthKit will return to this app.
    /// Health's type checkmark or "added today" is not this list.
    public func liveBodyFatSummary(limit: Int = 15) async -> String {
        let calendar = Calendar.current
        do {
            let samples = try await fetchNewestBodyFatSamples()
            await publishBodyFatTrace(makeBodyFatTrace(samples: samples, stage: "live"))
            let quantitySamples = samples
                .compactMap { $0 as? HKQuantitySample }
                .sorted { max($0.startDate, $0.endDate) > max($1.startDate, $1.endDate) }
            lastBodyFatFacts = makeBodyFatFacts(quantitySamples: quantitySamples, calendar: calendar)
            if quantitySamples.isEmpty {
                return "hk_live count=0 bodyfat=none"
            }
            let sliced = Array(quantitySamples.prefix(limit))
            var header = "hk_live count=\(quantitySamples.count) showing=\(sliced.count)"
            if let day = lastBodyFatFacts.hkDay, let percent = lastBodyFatFacts.hkPercent {
                header += " newest=\(day) bodyfat=\(percent)%"
            }
            return header
        } catch {
            lastBodyFatFacts = .empty
            await publishBodyFatTrace(
                makeBodyFatTrace(
                    samples: [],
                    stage: "live",
                    queryError: error.localizedDescription
                )
            )
            return "hk_live error=\(error.localizedDescription)"
        }
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
            publishSnapshots(for: affectedFamilies)
        }
        try? persistMetadata()
    }

    private func syncKind(_ kind: HealthKitSampleKind) async -> HealthKitIngestOutcome {
        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)

        defer {
            signpost.end(id: signpostID)
        }

        do {
            if kind == .bodyFatPercentage {
                try await resetBodyFatAnchorIfHealthKitIsAhead()
            }

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

            var sampleCount = delta.addedQuantitySamples.count
                + delta.addedSleepSamples.count
                + delta.addedWorkouts.count
            let deletedCount = delta.deletedSampleIDs.count

            var families = try writer.apply(delta: delta)

            if kind.isCumulativeDailyTotal {
                let extraDays = Set(delta.addedQuantitySamples.map {
                    HelmDay.day(for: $0.start, cutoff: .default, calendar: .current)
                })
                try await CumulativeDailyTotalsOverlay(store: store, writer: writer)
                    .refresh(kind: kind, extraDays: extraDays)
                families.insert(kind.metricFamily)
            }

            if kind == .bodyFatPercentage {
                do {
                    let overlay = try await ingestNewestBodyFatSamples()
                    families.formUnion(overlay.families)
                    if sampleCount == 0 {
                        sampleCount = overlay.ingestedCount
                    }
                } catch {
                    await diagnosticsLog.capture(
                        error: error,
                        category: .healthKitIngest,
                        message: "Body fat overlay failed",
                        context: ["sampleType": kind.rawValue]
                    )
                    if lastBodyFatTrace.overlayError == nil {
                        await publishBodyFatTrace(
                            makeBodyFatTrace(
                                samples: [],
                                stage: "overlay",
                                overlayError: error.localizedDescription
                            )
                        )
                    }
                }
            }

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

    /// Anchored ingest can skip samples and still save the cursor. If HealthKit's
    /// newest body-fat sample is later than GRDB, rewind that kind once per process.
    private func resetBodyFatAnchorIfHealthKitIsAhead() async throws {
        let newest = try await store.fetchNewestSamples(
            sampleType: HealthKitSampleKind.bodyFatPercentage.sampleType,
            limit: 1
        )
        guard let newestSample = newest.first else { return }
        let hkDate = max(newestSample.startDate, newestSample.endDate)
        let stored = try persistence.bodyComposition.fetchLatestWithBodyFat(
            onOrBefore: HelmDay.day(for: Date(), calendar: .current)
        )
        if let stored, stored.measuredAt.addingTimeInterval(1) >= hkDate {
            return
        }
        let context: [String: String] = [
            "hkDay": HelmDay.day(for: hkDate, calendar: .current).formatted,
            "storedDay": stored?.helmDay.formatted ?? "none",
        ]
        if didResetBodyFatAnchorThisProcess {
            await diagnosticsLog.record(
                category: .healthKitIngest,
                level: .error,
                message: "Body fat store still behind HealthKit after anchor reset",
                context: context
            )
            let hkDay = context["hkDay"] ?? "none"
            let storedDay = context["storedDay"] ?? "none"
            log.info(
                "Body fat still lagging after anchor reset hkDay=\(hkDay, privacy: .public) storedDay=\(storedDay, privacy: .public)"
            )
            return
        }
        try await anchorStore.resetAnchor(for: .bodyFatPercentage)
        didResetBodyFatAnchorThisProcess = true
        await diagnosticsLog.record(
            category: .healthKitIngest,
            level: .info,
            message: "Reset body fat anchor; HealthKit newer than stored",
            context: context
        )
        log.info("Reset body fat anchor; HealthKit newer than stored")
    }

    /// Anchored queries can skip samples and still advance the cursor. Merge the
    /// newest HealthKit body-fat rows so Coach is not stuck on an old GRDB date.
    private func ingestNewestBodyFatSamples() async throws -> (families: Set<HealthKitMetricFamily>, ingestedCount: Int) {
        let samples = try await fetchNewestBodyFatSamples()
        guard !samples.isEmpty else {
            await publishBodyFatTrace(makeBodyFatTrace(samples: [], stage: "overlay"))
            return ([], 0)
        }

        let delta = IngestSampleMapper.delta(
            kind: .bodyFatPercentage,
            addedSamples: samples,
            deletedObjectIDs: [],
            ownBundleID: ownBundleID
        )

        let acceptedCount = delta.addedQuantitySamples.filter { sample in
            BodyFatPercent.storedPercent(fromHealthKitPercentUnit: sample.value) != nil
        }.count
        if acceptedCount == 0 {
            await publishBodyFatTrace(makeBodyFatTrace(samples: samples, stage: "overlay"))
            return ([], 0)
        }

        let families: Set<HealthKitMetricFamily>
        do {
            families = try writer.apply(delta: delta)
        } catch {
            await publishBodyFatTrace(
                makeBodyFatTrace(
                    samples: samples,
                    stage: "overlay",
                    overlayError: error.localizedDescription
                )
            )
            throw error
        }
        await publishBodyFatTrace(makeBodyFatTrace(samples: samples, stage: "overlay"))
        return (families, acceptedCount)
    }

    private func fetchNewestBodyFatSamples() async throws -> [HKSample] {
        try await store.fetchNewestSamples(
            sampleType: HealthKitSampleKind.bodyFatPercentage.sampleType,
            limit: 50
        )
    }

    private enum BodyFatSampleDisposition {
        case kept
        case ownSource
        case incompatibleUnit
        case outOfRange
        case notQuantity
    }

    private func disposition(for sample: HKSample) -> BodyFatSampleDisposition {
        guard let quantitySample = sample as? HKQuantitySample else { return .notQuantity }
        let bundleID = quantitySample.sourceRevision.source.bundleIdentifier
        if !IngestSampleFilter.shouldIngest(sourceBundleID: bundleID, ownBundleID: ownBundleID) {
            return .ownSource
        }
        if BodyFatQuantity.storedPercent(from: quantitySample.quantity) != nil {
            return .kept
        }
        if quantitySample.quantity.is(compatibleWith: .percent()) {
            return .outOfRange
        }
        return .incompatibleUnit
    }

    private func makeBodyFatTrace(
        samples: [HKSample],
        stage: String,
        overlayError: String? = nil,
        queryError: String? = nil
    ) -> BodyFatQueryTrace {
        var kept = 0
        var own = 0
        var unit = 0
        var range = 0
        var notQuantity = 0
        var sources: Set<String> = []
        var newest: Date?
        for sample in samples {
            if let quantitySample = sample as? HKQuantitySample {
                sources.insert(quantitySample.sourceRevision.source.bundleIdentifier)
            }
            let measured = max(sample.startDate, sample.endDate)
            if newest.map({ measured > $0 }) ?? true {
                newest = measured
            }
            switch disposition(for: sample) {
            case .kept: kept += 1
            case .ownSource: own += 1
            case .incompatibleUnit: unit += 1
            case .outOfRange: range += 1
            case .notQuantity: notQuantity += 1
            }
        }
        let stored = try? persistence.bodyComposition.fetchLatestWithBodyFat(
            onOrBefore: HelmDay.day(for: Date(), calendar: .current)
        )
        let newestHkDay = newest.map { HelmDay.day(for: $0, calendar: .current).formatted }
        let storedDay = stored?.helmDay.formatted
        let sourceList = sources.sorted()
        let sourcesText: String
        if sourceList.isEmpty {
            sourcesText = "none"
        } else if sourceList.count <= 4 {
            sourcesText = sourceList.joined(separator: ",")
        } else {
            sourcesText = sourceList.prefix(4).joined(separator: ",") + "+\(sourceList.count - 4)"
        }
        return BodyFatQueryTrace(
            probedAt: Date(),
            hkSampleCount: samples.count,
            newestHkDay: newestHkDay,
            storedDay: storedDay,
            keptCount: kept,
            skippedOwnSource: own,
            skippedIncompatibleUnit: unit,
            skippedOutOfRange: range,
            skippedNotQuantity: notQuantity,
            overlayError: overlayError,
            queryError: queryError,
            sources: sourcesText,
            lag: BodyFatQueryTrace.lag(newestHkDay: newestHkDay, storedDay: storedDay),
            stage: stage
        )
    }

    private func makeBodyFatFacts(
        quantitySamples: [HKQuantitySample],
        calendar: Calendar
    ) -> BodyFatLatestFacts {
        var hkDay: String?
        var hkPercent: Double?
        var hkSource: String?
        for sample in quantitySamples {
            guard let stored = BodyFatQuantity.storedPercent(from: sample.quantity) else { continue }
            let measured = max(sample.startDate, sample.endDate)
            hkDay = HelmDay.day(for: measured, calendar: calendar).formatted
            hkPercent = stored
            hkSource = sample.sourceRevision.source.bundleIdentifier
            break
        }
        let storedRow = try? persistence.bodyComposition.fetchLatestWithBodyFat(
            onOrBefore: HelmDay.day(for: Date(), calendar: calendar)
        )
        return BodyFatLatestFacts(
            hkDay: hkDay,
            hkPercent: hkPercent,
            storeDay: storedRow?.helmDay.formatted,
            storePercent: storedRow?.bodyFatPercentage,
            hkReadableCount: quantitySamples.count,
            hkSource: hkSource
        )
    }

    private func publishBodyFatTrace(_ trace: BodyFatQueryTrace) async {
        lastBodyFatTrace = trace
        let level: LogLevel = (trace.queryError != nil || trace.overlayError != nil) ? .error : .info
        await diagnosticsLog.record(
            category: .healthKitIngest,
            level: level,
            message: "Body fat HealthKit probe",
            context: trace.diagnosticContext
        )
        let line = trace.logLine
        log.info("Body fat probe \(line, privacy: .public)")
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
