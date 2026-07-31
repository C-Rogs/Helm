import Core
import Diagnostics
import Foundation
import NutritionKit
import Persistence
import PlanKit

/// How much to trust today's HealthKit active-energy aggregate for energy-balance UI.
public enum ActiveEnergyFreshness: Sendable, Equatable {
    case unavailable
    case stale(partialKilocalories: Int?)
    case fresh(kilocalories: Int)

    public var displayKilocalories: Int? {
        switch self {
        case .unavailable: nil
        case let .stale(partial): partial
        case let .fresh(kilocalories): kilocalories
        }
    }

    public var isTrustworthyForTargetAdjustment: Bool {
        if case .fresh = self { return true }
        return false
    }
}

public enum ActiveEnergyDisplayCopy {
    public static let freshDetail = "From Apple Health"
    public static let stalePending = "Apple Health is still syncing today's activity"
    public static let stalePartial = "Still catching up - refresh after your workout"
    public static let unavailableDetail = "No active energy logged in Health yet"
}

public enum ActiveEnergyFreshnessResolver {
    public static let postWorkoutCatchUpWindow: TimeInterval = 3 * 60 * 60
    public static let lowBurnMisleadingThresholdKcal = 100

    public struct Context: Sendable, Equatable {
        public let helmDay: HelmDay
        public let activeEnergyKcal: Int?
        public let dayType: NutritionDayType
        public let isToday: Bool
        public let latestWorkoutEndedAt: Date?
        public let now: Date

        public init(
            helmDay: HelmDay,
            activeEnergyKcal: Int?,
            dayType: NutritionDayType,
            isToday: Bool,
            latestWorkoutEndedAt: Date?,
            now: Date
        ) {
            self.helmDay = helmDay
            self.activeEnergyKcal = activeEnergyKcal
            self.dayType = dayType
            self.isToday = isToday
            self.latestWorkoutEndedAt = latestWorkoutEndedAt
            self.now = now
        }
    }

    public static func resolve(_ context: Context) -> ActiveEnergyFreshness {
        let kilocalories = context.activeEnergyKcal

        guard context.isToday else {
            guard let kilocalories, kilocalories > 0 else { return .unavailable }
            return .fresh(kilocalories: kilocalories)
        }

        let recentWorkout = context.latestWorkoutEndedAt.map {
            context.now.timeIntervalSince($0) < postWorkoutCatchUpWindow
        } ?? false
        let expectsCatchUp = context.dayType == .training || recentWorkout

        if let kilocalories, kilocalories > 0 {
            if recentWorkout, kilocalories < lowBurnMisleadingThresholdKcal {
                return .stale(partialKilocalories: kilocalories)
            }
            return .fresh(kilocalories: kilocalories)
        }

        if expectsCatchUp {
            return .stale(partialKilocalories: nil)
        }
        return .unavailable
    }
}

public struct EnergyBalanceSummary: Sendable, Equatable {
    public let intakeKcal: Int?
    public let baseTargetKcal: Int
    public let adjustedTargetKcal: Int?
    public let activeEnergy: ActiveEnergyFreshness

    public init(
        intakeKcal: Int?,
        baseTargetKcal: Int,
        adjustedTargetKcal: Int?,
        activeEnergy: ActiveEnergyFreshness
    ) {
        self.intakeKcal = intakeKcal
        self.baseTargetKcal = baseTargetKcal
        self.adjustedTargetKcal = adjustedTargetKcal
        self.activeEnergy = activeEnergy
    }

    public static func build(
        intakeKcal: Int?,
        baseTargetKcal: Int,
        activeEnergy: ActiveEnergyFreshness
    ) -> EnergyBalanceSummary {
        let adjustedTargetKcal: Int?
        if activeEnergy.isTrustworthyForTargetAdjustment,
           case let .fresh(burned) = activeEnergy,
           baseTargetKcal > 0 {
            adjustedTargetKcal = baseTargetKcal + burned
        } else {
            adjustedTargetKcal = nil
        }

        return EnergyBalanceSummary(
            intakeKcal: intakeKcal,
            baseTargetKcal: baseTargetKcal,
            adjustedTargetKcal: adjustedTargetKcal,
            activeEnergy: activeEnergy
        )
    }
}

public struct NutritionDaySnapshot: Sendable, Equatable {
    public let helmDay: HelmDay
    public let targets: MacroTargets
    public let actual: NutritionDay?
    public let trend: NutritionTrendState
    public let dayType: NutritionDayType
    public let phase: TrainingPhase
    public let profileMaintenanceKcal: Int?
    public let activeEnergyKcal: Int?
    public let activeEnergyFreshness: ActiveEnergyFreshness
    public let energyBalance: EnergyBalanceSummary
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
        activeEnergyFreshness: ActiveEnergyFreshness = .unavailable,
        energyBalance: EnergyBalanceSummary? = nil,
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
        self.activeEnergyFreshness = activeEnergyFreshness
        self.energyBalance = energyBalance ?? EnergyBalanceSummary.build(
            intakeKcal: actual?.totalEnergy.map { Int($0.kilocalories.rounded()) },
            baseTargetKcal: targets.caloriesKcal,
            activeEnergy: activeEnergyFreshness
        )
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
        prescriptionSummary: PrescribedSessionSummary?,
        now: Date = Date()
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
        let activeEnergyKcal = dailyMetrics?.activeEnergy.map { Int($0.kilocalories.rounded()) }
        let today = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        let activeEnergyFreshness = ActiveEnergyFreshnessResolver.resolve(
            ActiveEnergyFreshnessResolver.Context(
                helmDay: day,
                activeEnergyKcal: activeEnergyKcal,
                dayType: dayType,
                isToday: day == today,
                latestWorkoutEndedAt: latestWorkoutEndedAt(on: day),
                now: now
            )
        )
        let intakeKcal = actual?.totalEnergy.map { Int($0.kilocalories.rounded()) }
        let energyBalance = EnergyBalanceSummary.build(
            intakeKcal: intakeKcal,
            baseTargetKcal: targets.caloriesKcal,
            activeEnergy: activeEnergyFreshness
        )

        return NutritionDaySnapshot(
            helmDay: day,
            targets: targets,
            actual: actual,
            trend: trend,
            dayType: dayType,
            phase: settings.phaseGoal.phase,
            profileMaintenanceKcal: profileMaintenanceKcal,
            activeEnergyKcal: activeEnergyKcal,
            activeEnergyFreshness: activeEnergyFreshness,
            energyBalance: energyBalance,
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

    private func latestWorkoutEndedAt(on day: HelmDay) -> Date? {
        guard let sessions = try? persistence.workoutSessions.fetchCompletedSessionsForPrescription(
            since: day,
            calendar: calendar,
            cutoff: cutoff
        ) else {
            return nil
        }

        return sessions.compactMap { session -> Date? in
            guard session.status == .completed else { return nil }
            let endedAt = session.endedAt ?? session.startedAt
            let sessionDay = HelmDay.day(for: endedAt, cutoff: cutoff, calendar: calendar)
            guard sessionDay == day else { return nil }
            return endedAt
        }.max()
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
