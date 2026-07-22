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

    public init(engine: ReadinessEngine) {
        self.engine = engine
    }

    public func refresh() async {
        do {
            state = try await engine.dashboardState(for: today())
        } catch {
            state = .awaitingData
        }
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

        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        let score = ReadinessKit.readiness(
            for: day,
            history: history,
            baselineState: baseline,
            calendar: calendar,
            cutoff: cutoff
        )
        signpost.end(id: signpostID)

        guard let score else { return nil }

        let payload = try encode(score)
        try persistence.readiness.upsertScore(helmDay: day, scoreJSON: payload)
        return score
    }

    private func loadBaselineState() throws -> ReadinessBaselineState? {
        guard let json = try persistence.readiness.fetchBaselineJSON() else {
            return nil
        }
        return try decode(ReadinessBaselineState.self, from: json)
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
