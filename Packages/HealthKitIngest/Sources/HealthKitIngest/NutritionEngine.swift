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
    /// Profile-based maintenance estimate (Mifflin-St Jeor seed) for transparency.
    public let profileMaintenanceKcal: Int?
    /// Active energy burned today from HealthKit (informational).
    public let activeEnergyKcal: Int?
    /// User marked logging complete for this day.
    public let loggingComplete: Bool

    public init(
        helmDay: HelmDay,
        targets: MacroTargets,
        actual: NutritionDay?,
        trend: NutritionTrendState,
        dayType: NutritionDayType,
        phase: TrainingPhase,
        profileMaintenanceKcal: Int? = nil,
        activeEnergyKcal: Int? = nil,
        loggingComplete: Bool = false
    ) {
        self.helmDay = helmDay
        self.targets = targets
        self.actual = actual
        self.trend = trend
        self.dayType = dayType
        self.phase = phase
        self.profileMaintenanceKcal = profileMaintenanceKcal
        self.activeEnergyKcal = activeEnergyKcal
        self.loggingComplete = loggingComplete
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
        let bodyProfile = resolvedBodyProfile(for: day)
        let profileMaintenanceKcal = bodyProfile
            .flatMap { BodyProfileTDEE.seedTDEEKcal(profile: $0) }
            .map { Int($0.rounded()) }

        let targetMuscles = targetMuscles(for: day, emphasis: settings.phaseGoal.emphasis)
        let mesocycleState = loadMesocycleState()
        let dayType = NutritionDayTypeResolver.resolve(
            prescriptionSummary: prescriptionSummary,
            targetMuscles: targetMuscles,
            mesocycleState: mesocycleState
        )

        var trend = trendStore.loadSafely()
        NutritionKit.healTrendState(&trend, bodyProfile: bodyProfile)
        var workingTrend = trend
        if let updated = try? NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &workingTrend,
            through: day,
            bodyProfile: bodyProfile,
            calendar: calendar
        ) {
            trend = updated
        }
        NutritionKit.healTrendState(&trend, bodyProfile: bodyProfile)
        try? trendStore.save(trend)

        let targets = NutritionKit.targets(
            for: NutritionTargetContext(bodyProfile: bodyProfile, dayType: dayType, loggedDay: actual),
            phase: settings.phaseGoal,
            trend: trend
        )
        let loggingComplete = (try? persistence.nutritionLogStatus.isLoggingComplete(helmDay: day)) ?? false

        return NutritionDaySnapshot(
            helmDay: day,
            targets: targets,
            actual: actual,
            trend: trend,
            dayType: dayType,
            phase: settings.phaseGoal.phase,
            profileMaintenanceKcal: profileMaintenanceKcal,
            activeEnergyKcal: dailyMetrics?.activeEnergy.map { Int($0.kilocalories.rounded()) },
            loggingComplete: loggingComplete
        )
    }

    public func refreshTrend(through day: HelmDay) throws {
        let bodyProfile = resolvedBodyProfile(for: day)
        var trend = trendStore.loadSafely()
        trend = try NutritionTrendBuilder.updatedTrend(
            from: persistence,
            state: &trend,
            through: day,
            bodyProfile: bodyProfile,
            calendar: calendar
        )
        try trendStore.save(trend)
    }

    private func resolvedBodyProfile(for day: HelmDay) -> BodyProfile? {
        let store = BodyProfileStore(metadata: persistence.appMetadata)
        guard var profile = store.load(), profile.isComplete else { return nil }
        if
            let bodyMassKg = try? persistence.bodyComposition
                .fetchLatest(onOrBefore: day, limit: 1)
                .first?
                .mass
                .kilograms,
            bodyMassKg > 1
        {
            profile = profile.withUpdatedBodyMassKg(bodyMassKg)
        }
        guard profile.ageYears() >= 13 else { return nil }
        return profile
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
