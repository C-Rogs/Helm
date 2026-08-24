import Core
import Diagnostics
import Foundation
import Observation
import OSLog
import Persistence
import ReadinessKit

public enum ReadinessDashboardState: Sendable, Equatable {
    case loading
    case awaitingData
    case buildingBaseline(validNights: Int, message: String)
    case scored(ReadinessScore)

    public var score: ReadinessScore? {
        if case let .scored(score) = self {
            return score
        }
        return nil
    }
}

@MainActor
@Observable
public final class ReadinessService {
    public private(set) var state: ReadinessDashboardState = .loading

    private let engine: ReadinessEngine
    private var refreshTask: Task<Void, Never>?

    public init(engine: ReadinessEngine) {
        self.engine = engine
    }

    /// Paint last persisted score immediately (no 180-day history rebuild).
    /// Call before `refresh()` so ARC is not stuck on `.loading`.
    public func hydrateFromCache() async {
        guard case .loading = state else { return }
        do {
            guard let cached = try await engine.cachedDashboardState(for: today()) else { return }
            await reclaimMainThread()
            guard case .loading = state else { return }
            state = cached
        } catch {
            // Cache miss / decode failure: stay loading until refresh.
        }
    }

    public func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor in
            await self.hydrateFromCache()
            do {
                let next = try await self.engine.dashboardState(for: self.today())
                // Actor hop from ReadinessEngine can resume off the real main thread;
                // assign Observable state only after a real main-queue hop.
                await self.reclaimMainThread()
                self.state = next
            } catch {
                await self.reclaimMainThread()
                if case .loading = self.state {
                    self.state = .awaitingData
                }
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    public func recomputeAfterIngest(affectedFamilies: Set<HealthKitMetricFamily>) async {
        guard Self.readinessFamilies.intersection(affectedFamilies).isEmpty == false else { return }
        await refresh()
    }

    public func seedBaselinesFromBackfill(window: BackfillWindow) async {
        do {
            try await engine.seedBaselines(from: window)
            await refresh()
        } catch {
            // Baseline seed failure is logged inside the engine.
        }
    }

    nonisolated private static func reclaimMainThread() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func reclaimMainThread() async {
        await Self.reclaimMainThread()
    }

    private func today(calendar: Calendar = .current, cutoff: DayCutoff = .default) -> HelmDay {
        HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
    }

    private static let readinessFamilies: Set<HealthKitMetricFamily> = [.vitals, .sleep, .workouts]
}

public actor ReadinessEngine {
    private let persistence: PersistenceStore
    private let signpost: HelmSignpost
    private let log: Logger
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    public init(
        persistence: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.cutoff = cutoff
        signpost = HelmSignpost(name: .readinessCompute, category: .readinessKit)
        log = helmLogger(category: .readinessKit)
    }

    /// One-time conversion of legacy per-sample TRIMP sums to duration-weighted scale.
    /// Pre-epoch values counted one full zone weight per HR sample (1 Hz ≈ 60x the
    /// minutes-integral). Scaling stored history and clearing the seeded P75 keeps
    /// strain z-scores coherent while the new baseline EWMA settles in.
    public func migrateTRIMPEpochIfNeeded() throws {
        guard try persistence.appMetadata.value(forKey: Self.trimpEpochMigrationFlag) == nil else { return }

        let scaledDays = try persistence.dailyMetrics.scaleAllPriorDayTRIMP(by: 1.0 / 60.0)

        if let json = try persistence.readiness.fetchBaselineJSON(),
           var baseline = try? decode(ReadinessBaselineState.self, from: json) {
            baseline.trimpP75 = nil
            let payload = try encode(baseline)
            try persistence.readiness.upsertBaseline(stateJSON: payload)
        }

        try persistence.appMetadata.setValue("1", forKey: Self.trimpEpochMigrationFlag)
        log.info("TRIMP epoch migration applied: \(scaledDays) days rescaled, seeded P75 reset")
    }

    private static let trimpEpochMigrationFlag = "trimpEpoch2MigrationApplied"

    /// Last persisted score for `day`, or most recent prior day (stale paint only).
    /// Does not rebuild history or recompute.
    public func cachedDashboardState(for day: HelmDay) throws -> ReadinessDashboardState? {
        if let json = try persistence.readiness.fetchScoreJSON(helmDay: day) {
            return .scored(try decode(ReadinessScore.self, from: json))
        }
        // Morning launch often has yesterday scored and today not yet - show that until recompute.
        let recent = try persistence.readiness.fetchScores(endingAt: day, limit: 1)
        guard let (_, json) = recent.first else { return nil }
        return .scored(try decode(ReadinessScore.self, from: json))
    }

    public func dashboardState(for day: HelmDay) throws -> ReadinessDashboardState {
        let history = try ReadinessHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        let validNights = ReadinessKit.validNightCount(in: history, through: day)

        if let message = ReadinessKit.buildingBaselineMessage(validNights: validNights) {
            return .buildingBaseline(validNights: validNights, message: message)
        }

        guard let score = try computeAndPersist(for: day, history: history) else {
            return .awaitingData
        }

        return .scored(score)
    }

    public func recompute(for day: HelmDay) throws -> ReadinessScore? {
        let history = try ReadinessHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        return try computeAndPersist(for: day, history: history)
    }

    public func seedBaselines(from window: BackfillWindow) throws {
        let history = try ReadinessHistoryBuilder.history(
            from: persistence,
            window: window,
            calendar: calendar,
            cutoff: cutoff
        )
        let baseline = ReadinessKit.seedBaselines(from: history)
        let payload = try encode(baseline)
        try persistence.readiness.upsertBaseline(stateJSON: payload)
        log.info("Persisted readiness baselines from backfill (\(baseline.seededNightCount) nights)")
    }

    private func computeAndPersist(for day: HelmDay, history: [ReadinessDayInput]) throws -> ReadinessScore? {
        let baseline = try loadBaselineState()
        let previousBand = loadPreviousBand(before: day)

        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        let score = ReadinessKit.readiness(
            for: day,
            history: history,
            baselineState: baseline,
            previousBand: previousBand,
            calendar: calendar,
            cutoff: cutoff
        )
        signpost.end(id: signpostID)

        guard let score else { return nil }

        let payload = try encode(score)
        try persistence.readiness.upsertScore(helmDay: day, scoreJSON: payload)

        // Incrementally update baseline from today's data and persist.
        if let todayInput = history.first(where: { $0.helmDay == day }) {
            let updated = (baseline ?? ReadinessBaselineState()).updating(today: todayInput, history: history)
            let baselinePayload = try encode(updated)
            try persistence.readiness.upsertBaseline(stateJSON: baselinePayload)
        }

        return score
    }

    private func loadBaselineState() throws -> ReadinessBaselineState? {
        guard let json = try persistence.readiness.fetchBaselineJSON() else {
            return nil
        }
        return try decode(ReadinessBaselineState.self, from: json)
    }

    /// Yesterday's persisted band feeds the ±3 hysteresis deadband so scores hovering
    /// near 34/67 stop flipping bands day to day.
    private func loadPreviousBand(before day: HelmDay) -> ReadinessBand? {
        let priorDay = day.adding(days: -1, calendar: calendar)
        do {
            if let json = try persistence.readiness.fetchScoreJSON(helmDay: priorDay) {
                return try decode(ReadinessScore.self, from: json).band
            }
            let recent = try persistence.readiness.fetchScores(endingAt: priorDay, limit: 1)
            if let (_, json) = recent.first {
                return try decode(ReadinessScore.self, from: json).band
            }
        } catch {
            log.warning("Previous readiness band unavailable for hysteresis: \(error.localizedDescription)")
        }
        return nil
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try jsonEncoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ReadinessServiceError.encodingFailed
        }
        return json
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw ReadinessServiceError.decodingFailed
        }
        return try jsonDecoder.decode(type, from: data)
    }
}

public enum ReadinessServiceError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}
