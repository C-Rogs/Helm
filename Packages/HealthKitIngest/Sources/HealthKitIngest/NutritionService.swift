import Core
import Foundation
import Observation
import ReadinessKit

public enum NutritionDashboardState: Sendable, Equatable {
    case loading
    case ready(NutritionDaySnapshot)

    public var snapshot: NutritionDaySnapshot? {
        if case let .ready(snapshot) = self {
            return snapshot
        }
        return nil
    }
}

@MainActor
@Observable
public final class NutritionService {
    public private(set) var state: NutritionDashboardState = .loading

    private let engine: NutritionEngine

    public init(engine: NutritionEngine) {
        self.engine = engine
    }

    public func refresh(prescriptionSummary: PrescribedSessionSummary?) async {
        await refresh(for: today(), prescriptionSummary: prescriptionSummary)
    }

    public func refresh(for helmDay: HelmDay, prescriptionSummary: PrescribedSessionSummary?) async {
        let snapshot = await engine.snapshot(
            for: helmDay,
            prescriptionSummary: prescriptionSummary
        )
        state = .ready(snapshot)
    }

    public func recomputeAfterIngest(affectedFamilies: Set<HealthKitMetricFamily>) async {
        guard Self.nutritionFamilies.intersection(affectedFamilies).isEmpty == false else { return }
        let day = today()
        do {
            try await engine.refreshTrend(through: day)
        } catch {
            // Trend refresh failure is non-fatal; dashboard refresh will retry.
        }
    }

    private func today(calendar: Calendar = .current, cutoff: DayCutoff = .default) -> HelmDay {
        HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
    }

    private static let nutritionFamilies: Set<HealthKitMetricFamily> = [.nutrition, .bodyComposition]
}
