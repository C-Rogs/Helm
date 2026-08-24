import Core
import Diagnostics
import Foundation
import HealthKit
import OSLog
import Persistence
import ReadinessKit

public actor BackfillService {
    public static let defaultOwnBundleID = HealthKitIngest.defaultOwnBundleID

    private let store: any HealthKitStoreClient
    private let persistence: PersistenceStore
    private let cursorStore: BackfillCursorStore
    private let writer: IngestPersistenceWriter
    private let ownBundleID: String
    private let diagnosticsLog: DiagnosticsLog
    private let signpost: HelmSignpost
    private let readinessEngine: ReadinessEngine?
    private let log: Logger
    private let calendar: Calendar

    private var runningTask: Task<Void, Never>?

    public init(
        persistence: PersistenceStore,
        anchorDirectoryURL: URL,
        ownBundleID: String = defaultOwnBundleID,
        store: any HealthKitStoreClient = LiveHealthKitStore(),
        diagnosticsLog: DiagnosticsLog = .shared,
        readinessEngine: ReadinessEngine? = nil,
        calendar: Calendar = .current
    ) {
        self.persistence = persistence
        cursorStore = BackfillCursorStore(directoryURL: anchorDirectoryURL)
        writer = IngestPersistenceWriter(store: persistence, calendar: calendar)
        self.ownBundleID = ownBundleID
        self.store = store
        self.diagnosticsLog = diagnosticsLog
        self.readinessEngine = readinessEngine
        signpost = HelmSignpost(name: .backfillChunk, category: .healthKitIngest)
        log = helmLogger(category: .healthKitIngest)
        self.calendar = calendar
    }

    public func isComplete(for window: BackfillWindow) async -> Bool {
        let cursor = await cursorStore.cursor(for: window)
        return cursor.isFinished
    }

    public func savedProgress(for window: BackfillWindow = .sixMonths()) async -> BackfillProgress {
        let cursor = await cursorStore.cursor(for: window)
        let totalChunks = BackfillChunkPlanner.monthlyChunks(in: window, calendar: calendar).count
        return BackfillProgress(
            completedChunks: cursor.completedChunkIndices.count,
            totalChunks: totalChunks,
            samplesIngestedThisRun: 0,
            isComplete: cursor.isFinished
        )
    }

    public func resetCursor(for window: BackfillWindow) async throws {
        try await cursorStore.reset(for: window)
    }

    public func resetAllCursors() async throws {
        try await cursorStore.resetAll()
    }

    /// Runs bounded backfill off the caller's thread. Yields progress; completes when finished or cancelled.
    @discardableResult
    public func run(window: BackfillWindow) -> AsyncStream<BackfillProgress> {
        AsyncStream { continuation in
            let task = Task {
                await self.executeBackfill(window: window, continuation: continuation)
                continuation.finish()
            }
            self.runningTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Default six-month window; no-op when already complete for that window.
    public func runDefaultIfNeeded() -> AsyncStream<BackfillProgress> {
        let window = BackfillWindow.sixMonths(calendar: calendar)

        return AsyncStream { continuation in
            let task = Task {
                if await self.isComplete(for: window) {
                    continuation.yield(await self.savedProgress(for: window))
                    continuation.finish()
                    return
                }
                for await progress in self.run(window: window) {
                    continuation.yield(progress)
                }
                continuation.finish()
            }
            self.runningTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func effectiveWindow(for window: BackfillWindow, cursor: BackfillCursor) -> BackfillWindow {
        guard let anchoredStart = cursor.anchoredStart,
              let anchoredEnd = cursor.anchoredEnd
        else {
            return window
        }
        return BackfillWindow(start: anchoredStart, end: anchoredEnd, kind: window.kind)
    }

    private func executeBackfill(
        window: BackfillWindow,
        continuation: AsyncStream<BackfillProgress>.Continuation
    ) async {
        guard store.isHealthDataAvailable() else {
            log.warning("Backfill skipped: Health data unavailable")
            return
        }

        var storedCursor = await cursorStore.cursor(for: window)
        let executionWindow = effectiveWindow(for: window, cursor: storedCursor)
        if storedCursor.anchoredStart == nil, !storedCursor.isFinished {
            do {
                try await cursorStore.anchorWindow(window)
                storedCursor = await cursorStore.cursor(for: window)
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Backfill window anchor failed"
                )
            }
        }

        let chunks = BackfillChunkPlanner.monthlyChunks(in: executionWindow, calendar: calendar)
        guard !chunks.isEmpty else {
            continuation.yield(
                BackfillProgress(
                    completedChunks: 0,
                    totalChunks: 0,
                    samplesIngestedThisRun: 0,
                    isComplete: true
                )
            )
            return
        }

        let cursor = storedCursor
        if cursor.isFinished {
            continuation.yield(
                BackfillProgress(
                    completedChunks: chunks.count,
                    totalChunks: chunks.count,
                    samplesIngestedThisRun: 0,
                    isComplete: true
                )
            )
            return
        }

        var samplesIngestedThisRun = 0
        var completedCount = cursor.completedChunkIndices.count
        var processedNewChunks = false

        for chunk in chunks {
            if Task.isCancelled { return }
            if cursor.completedChunkIndices.contains(chunk.index) {
                continue
            }

            let signpostID = signpost.makeSignpostID()
            signpost.begin(id: signpostID)

            let chunkSamples: Int
            do {
                chunkSamples = try await ingestChunk(chunk)
            } catch {
                signpost.end(id: signpostID)
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Backfill chunk failed",
                    context: ["chunkIndex": String(chunk.index)]
                )
                return
            }

            signpost.end(id: signpostID)

            do {
                try await cursorStore.markChunkComplete(
                    chunk.index,
                    for: window,
                    totalChunks: chunks.count
                )
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Backfill cursor persist failed",
                    context: ["chunkIndex": String(chunk.index)]
                )
                return
            }

            samplesIngestedThisRun += chunkSamples
            completedCount += 1
            processedNewChunks = true

            let isComplete = completedCount >= chunks.count
            continuation.yield(
                BackfillProgress(
                    completedChunks: completedCount,
                    totalChunks: chunks.count,
                    samplesIngestedThisRun: samplesIngestedThisRun,
                    isComplete: isComplete
                )
            )

            log.info(
                "Backfill chunk \(chunk.index) complete: \(chunkSamples) samples (\(completedCount)/\(chunks.count))"
            )
        }

        if processedNewChunks, completedCount >= chunks.count {
            do {
                if let readinessEngine {
                    try await readinessEngine.seedBaselines(from: window)
                } else {
                    let baseline = try BackfillBaselineSeed.seedBaselines(
                        from: persistence,
                        window: window,
                        calendar: calendar
                    )
                    log.info(
                        "Readiness baselines seeded from backfill (\(baseline.seededNightCount) nights)"
                    )
                }
            } catch {
                await diagnosticsLog.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "Baseline seed after backfill failed"
                )
            }
        }
    }

    private func ingestChunk(_ chunk: BackfillChunk) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(
            withStart: chunk.start,
            end: chunk.end,
            options: [.strictStartDate]
        )

        var sampleCount = 0
        var trimpByTargetDay: [HelmDay: Double] = [:]

        for kind in HealthKitSampleKind.allCases {
            if Task.isCancelled { return sampleCount }

            let samples = try await store.fetchSamples(
                sampleType: kind.sampleType,
                predicate: predicate,
                limit: BackfillChunkPlanner.maximumSamplesPerQuery
            )

            var delta = IngestSampleMapper.delta(
                kind: kind,
                addedSamples: samples,
                deletedObjectIDs: [],
                ownBundleID: ownBundleID
            )

            if kind == .workout, !delta.addedWorkouts.isEmpty {
                // Live ingest computes TRIMP per workout; backfill must too, otherwise
                // historical days keep priorDayTRIMP = nil and strain baselines skew.
                let ingester = WorkoutTRIMPIngester(
                    store: store,
                    persistence: persistence,
                    calendar: calendar
                )
                trimpByTargetDay = try await ingester.trimpByTargetDay(for: delta.addedWorkouts)
                delta = IngestDelta(
                    kind: delta.kind,
                    addedQuantitySamples: delta.addedQuantitySamples,
                    addedSleepSamples: delta.addedSleepSamples,
                    addedWorkouts: delta.addedWorkouts,
                    deletedSampleIDs: delta.deletedSampleIDs,
                    trimpByTargetDay: trimpByTargetDay
                )
            }

            sampleCount += delta.addedQuantitySamples.count
                + delta.addedSleepSamples.count
                + delta.addedWorkouts.count

            _ = try writer.apply(delta: delta)
        }

        return sampleCount
    }
}
