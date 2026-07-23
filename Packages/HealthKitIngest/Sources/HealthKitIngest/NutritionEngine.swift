import Core
import Foundation
import NutritionKit
import Persistence
import PlanKit

public struct NutritionDaySnapshot: Sendable, Equatable {
    public let helmDay: HelmDay
    public let targets: MacroTargets
    public let actual: NutritionDay?
    public let trend: NutritionTrendState
    public let dayType: NutritionDayType
    public let phase: TrainingPhase

    public init(
        helmDay: HelmDay,
        targets: MacroTargets,
        actual: NutritionDay?,
        trend: NutritionTrendState,
        dayType: NutritionDayType,
        phase: TrainingPhase
    ) {
        self.helmDay = helmDay
        self.targets = targets
        self.actual = actual
        self.trend = trend
        self.dayType = dayType
        self.phase = phase
    }
}

public actor NutritionEngine {
    private let persistence: PersistenceStore
    private let trendStore: NutritionTrendStore
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let jsonDecoder = JSONDecoder()

    public init(
        persistence: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.persistence = persistence
        trendStore = NutritionTrendStore(metadata: persistence.appMetadata)
        self.calendar = calendar
        self.cutoff = cutoff
    }

    public func snapshot(
        for day: HelmDay,
        prescriptionSummary: PrescribedSessionSummary?
    ) throws -> NutritionDaySnapshot {
        let settings = try persistence.trainingPlan.load()
        let actual = try persistence.nutrition.fetchDay(helmDay: day)
        let bodyMassKg = try persistence.bodyComposition.fetchLatest(onOrBefore: day, limit: 1).first?.mass.kilograms
        let targetMuscles = targetMuscles(for: day, emphasis: settings.phaseGoal.emphasis)
        let mesocycleState = try loadMesocycleState()
        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: prescriptionSummary,
            targetMuscles: targetMuscles,
            mesocycleState: mesocycleState
        )

        var trend = try trendStore.load()
        trend = try NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &trend,
            through: day,
            calendar: calendar
        )
        try trendStore.save(trend)

        let targets = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: bodyMassKg, dayType: dayType, loggedDay: actual),
            phase: settings.phaseGoal,
            trend: trend
        )

        return NutritionDaySnapshot(
            helmDay: day,
            targets: targets,
            actual: actual,
            trend: trend,
            dayType: dayType,
            phase: settings.phaseGoal.phase
        )
    }

    public func refreshTrend(through day: HelmDay) throws {
        var trend = try trendStore.load()
        trend = try NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &trend,
            through: day,
            calendar: calendar
        )
        try trendStore.save(trend)
    }

    private func targetMuscles(for day: HelmDay, emphasis: String?) -> [MuscleGroup] {
        SessionSplitPlanner.targetMuscles(for: day, emphasis: emphasis, calendar: calendar)
    }

    private func loadMesocycleState() throws -> MesocycleState? {
        guard
            let json = try persistence.plan.loadMesocycleStateJSON(),
            let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? jsonDecoder.decode(MesocycleState.self, from: data)
    }
}

public enum NutritionServiceError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}
