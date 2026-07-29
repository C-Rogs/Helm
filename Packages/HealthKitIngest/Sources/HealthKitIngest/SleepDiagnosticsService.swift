import Core
import Foundation
import HealthKit
import Persistence

public struct SleepDiagnosticSample: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let stage: SleepAnalysisStage
    public let sourceBundleID: String?

    public init(
        id: UUID,
        start: Date,
        end: Date,
        stage: SleepAnalysisStage,
        sourceBundleID: String?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceBundleID = sourceBundleID
    }
}

public struct SleepDiagnosticsSnapshot: Sendable {
    public let wakeCalendarDay: Date
    public let windowStart: Date
    public let windowEnd: Date
    public let healthKitSummary: SleepNightSummary
    public let persistedSummary: SleepNightSummary
    public let healthKitSamples: [SleepDiagnosticSample]
    public let persistedRecords: [SleepRecord]

    public init(
        wakeCalendarDay: Date,
        windowStart: Date,
        windowEnd: Date,
        healthKitSummary: SleepNightSummary,
        persistedSummary: SleepNightSummary,
        healthKitSamples: [SleepDiagnosticSample],
        persistedRecords: [SleepRecord]
    ) {
        self.wakeCalendarDay = wakeCalendarDay
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.healthKitSummary = healthKitSummary
        self.persistedSummary = persistedSummary
        self.healthKitSamples = healthKitSamples
        self.persistedRecords = persistedRecords
    }
}

/// Compares raw HealthKit sleep samples with Helm persisted intervals for one wake day.
public enum SleepDiagnosticsService {
    public static func loadLastNight(
        store: PersistenceStore,
        storeClient: any HealthKitStoreClient = LiveHealthKitStore(),
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) async throws -> SleepDiagnosticsSnapshot {
        let wakeDay = calendar.startOfDay(for: referenceDate)
        return try await load(
            wakeCalendarDay: wakeDay,
            store: store,
            storeClient: storeClient,
            calendar: calendar
        )
    }

    public static func load(
        wakeCalendarDay: Date,
        store: PersistenceStore,
        storeClient: any HealthKitStoreClient,
        calendar: Calendar = .current
    ) async throws -> SleepDiagnosticsSnapshot {
        let wakeDay = calendar.startOfDay(for: wakeCalendarDay)
        let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
        let windowEnd = SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)
        let queryEnd = calendar.date(byAdding: .second, value: 1, to: windowEnd) ?? windowEnd

        let persistedRecords = try store.sleep.fetchOverlapping(start: windowStart, end: windowEnd)
        let persistedSummary = SleepAggregation.nightSummary(
            from: persistedRecords,
            windowStart: windowStart,
            windowEnd: windowEnd
        )

        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return SleepDiagnosticsSnapshot(
                wakeCalendarDay: wakeDay,
                windowStart: windowStart,
                windowEnd: windowEnd,
                healthKitSummary: SleepNightSummary(asleepHours: nil),
                persistedSummary: persistedSummary,
                healthKitSamples: [],
                persistedRecords: persistedRecords
            )
        }

        let samples = try await storeClient.fetchSamples(
            sampleType: sleepType,
            predicate: HKQuery.predicateForSamples(withStart: windowStart, end: queryEnd),
            limit: HKObjectQueryNoLimit
        )

        let healthKitSamples = samples.compactMap { sample -> SleepDiagnosticSample? in
            guard let categorySample = sample as? HKCategorySample,
                  let stage = IngestSampleMapper.sleepStage(for: categorySample.value) else {
                return nil
            }
            return SleepDiagnosticSample(
                id: categorySample.uuid,
                start: categorySample.startDate,
                end: categorySample.endDate,
                stage: stage,
                sourceBundleID: categorySample.sourceRevision.source.bundleIdentifier
            )
        }

        let healthKitRecords = healthKitSamples.map { sample in
            SleepRecord(
                id: sample.id,
                start: sample.start,
                end: sample.end,
                helmDay: SleepRecord.helmDay(forStart: sample.start, calendar: calendar),
                stage: sample.stage,
                sourceBundleID: sample.sourceBundleID
            )
        }
        let healthKitSummary = SleepAggregation.nightSummary(
            from: healthKitRecords,
            windowStart: windowStart,
            windowEnd: windowEnd
        )

        return SleepDiagnosticsSnapshot(
            wakeCalendarDay: wakeDay,
            windowStart: windowStart,
            windowEnd: windowEnd,
            healthKitSummary: healthKitSummary,
            persistedSummary: persistedSummary,
            healthKitSamples: healthKitSamples,
            persistedRecords: persistedRecords
        )
    }
}
