import Core
import Foundation
import NutritionKit
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

    private var weeklyBudgetReconcileTask: Task<Void, Never>?

    public init(engine: NutritionEngine) {
        self.engine = engine
    }

    public func refresh(prescriptionSummary: PrescribedSessionSummary?) async {
        await refresh(for: today(), prescriptionSummary: prescriptionSummary)
    }

    public func refresh(for helmDay: HelmDay, prescriptionSummary: PrescribedSessionSummary?) async {
        weeklyBudgetReconcileTask?.cancel()
        let reuse: WeeklyNutritionBudget?
        if let previous = state.snapshot?.weeklyBudget,
           previous.days.contains(where: { $0.day == helmDay }) {
            reuse = previous
        } else {
            reuse = nil
        }
        let snapshot = await engine.snapshot(
            for: helmDay,
            prescriptionSummary: prescriptionSummary,
            reuseWeeklyBudget: reuse
        )
        state = .ready(snapshot)
        if reuse != nil {
            weeklyBudgetReconcileTask = Task { [engine] in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                let full = await engine.snapshot(for: helmDay, prescriptionSummary: prescriptionSummary)
                guard !Task.isCancelled else { return }
                state = .ready(full)
            }
        }
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

    public func weeklyBudget(
        for helmDay: HelmDay,
        prescriptionSummary: PrescribedSessionSummary?
    ) async throws -> WeeklyNutritionBudget {
        try await engine.weeklyBudget(for: helmDay, prescriptionSummary: prescriptionSummary)
    }

    private func today(calendar: Calendar = .current, cutoff: DayCutoff = .default) -> HelmDay {
        HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
    }

    private static let nutritionFamilies: Set<HealthKitMetricFamily> = [.nutrition, .bodyComposition]
}
