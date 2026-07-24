import Core
import Diagnostics
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

    /// Always returns a snapshot with non-zero macro targets when training plan data is readable.
    public func snapshot(
        for day: HelmDay,
        prescriptionSummary: PrescribedSessionSummary?
    ) -> NutritionDaySnapshot {
        let settings = (try? persistence.trainingPlan.load()) ?? .default
        let storedDay = try? persistence.nutrition.fetchDay(helmDay: day)
        let dailyMetrics = try? persistence.dailyMetrics.fetch(helmDay: day)
        let meals = try? persistence.nutrition.fetchMeals(for: day)
        let actual = NutritionActualResolver.resolve(
            helmDay: day,
            storedDay: storedDay,
            dailyMetrics: dailyMetrics,
            meals: meals
        )
        let bodyMassKg = try? persistence.bodyComposition.fetchLatest(onOrBefore: day, limit: 1).first?.mass.kilograms
        let safeBodyMassKg = NutritionKit.resolvedBodyMassKg(bodyMassKg)
        let targetMuscles = targetMuscles(for: day, emphasis: settings.phaseGoal.emphasis)
        let mesocycleState = loadMesocycleState()
        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: prescriptionSummary,
            targetMuscles: targetMuscles,
            mesocycleState: mesocycleState
        )

        var trend = trendStore.loadSafely()
        NutritionKit.healTrendState(&trend, bodyMassKg: safeBodyMassKg)
        var workingTrend = trend
        if let updated = try? NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &workingTrend,
            through: day,
            calendar: calendar
        ) {
            trend = updated
        }
        NutritionKit.healTrendState(&trend, bodyMassKg: safeBodyMassKg)
        try? trendStore.save(trend)

        let targets = Self.ensuredTargets(
            bodyMassKg: safeBodyMassKg,
            dayType: dayType,
            phase: settings.phaseGoal,
            loggedDay: actual,
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
        var trend = trendStore.loadSafely()
        trend = try NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &trend,
            through: day,
            calendar: calendar
        )
        try trendStore.save(trend)
    }

    private static func ensuredTargets(
        bodyMassKg: Double,
        dayType: NutritionDayType,
        phase: PhaseGoal,
        loggedDay: NutritionDay?,
        trend: NutritionTrendState
    ) -> MacroTargets {
        let context = NutritionTargetContext(
            bodyMassKg: bodyMassKg,
            dayType: dayType,
            loggedDay: loggedDay
        )
        let primary = NutritionKit.targets(for: context, phase: phase, trend: trend)
        if primary.caloriesKcal > 0, primary.proteinGrams > 0 {
            return primary
        }

        Task {
            await DiagnosticsLog.shared.record(
                category: .nutritionKit,
                level: .info,
                message: "Macro targets cold-start fallback",
                context: [
                    "primaryCalories": String(primary.caloriesKcal),
                    "estimatedTDEE": String(primary.estimatedTDEEKcal)
                ]
            )
        }

        let fallback = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: bodyMassKg, dayType: dayType, loggedDay: loggedDay),
            phase: phase,
            trend: NutritionTrendState()
        )
        if fallback.caloriesKcal > 0, fallback.proteinGrams > 0 {
            return fallback
        }

        return NutritionKit.targets(
            for: NutritionTargetContext(
                bodyMassKg: NutritionKit.resolvedBodyMassKg(nil),
                dayType: dayType,
                loggedDay: loggedDay
            ),
            phase: PhaseGoal(phase: .maintain),
            trend: NutritionTrendState()
        )
    }

    private func targetMuscles(for day: HelmDay, emphasis: String?) -> [MuscleGroup] {
        SessionSplitPlanner.targetMuscles(for: day, emphasis: emphasis, calendar: calendar)
    }

    private func loadMesocycleState() -> MesocycleState? {
        guard
            let json = try? persistence.plan.loadMesocycleStateJSON(),
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
