import Core
import Foundation
import NutritionKit
import Persistence
import PlanKit

public struct NutritionWeeklyCheckInDayRow: Sendable, Hashable, Identifiable, Equatable {
    public var id: String { helmDay.formatted }

    public let helmDay: HelmDay
    public let hasWeighIn: Bool
    public let hasFoodLog: Bool
    public let loggedKcal: Int?
    public let goalKcal: Int?
    public let loggingComplete: Bool
    public let isIncomplete: Bool
    public var isIncluded: Bool

    public init(
        helmDay: HelmDay,
        hasWeighIn: Bool,
        hasFoodLog: Bool,
        loggedKcal: Int?,
        goalKcal: Int?,
        loggingComplete: Bool,
        isIncomplete: Bool,
        isIncluded: Bool
    ) {
        self.helmDay = helmDay
        self.hasWeighIn = hasWeighIn
        self.hasFoodLog = hasFoodLog
        self.loggedKcal = loggedKcal
        self.goalKcal = goalKcal
        self.loggingComplete = loggingComplete
        self.isIncomplete = isIncomplete
        self.isIncluded = isIncluded
    }
}

public struct NutritionWeeklyCheckInPreview: Sendable, Equatable {
    public let asOf: HelmDay
    public let windowStart: HelmDay
    public let days: [NutritionWeeklyCheckInDayRow]
    public let confidence: NutritionWeeklyCheckInConfidence
    public let weighInDays: Int
    public let foodDays: Int
    public let currentCaloriesKcal: Int
    public let proposedCaloriesKcal: Int
    public let currentProteinGrams: Int
    public let proposedProteinGrams: Int
    public let currentTDEEKcal: Int
    public let proposedTDEEKcal: Int
    public let meetsSoftGate: Bool

    public var calorieDeltaKcal: Int { proposedCaloriesKcal - currentCaloriesKcal }
}

public actor NutritionWeeklyCheckInService {
    private let persistence: PersistenceStore
    private let trendStore: NutritionTrendStore
    private let calendar: Calendar
    private let cutoff: DayCutoff

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

    public func buildPreview(
        asOf: HelmDay,
        includedOverrides: [HelmDay: Bool]? = nil
    ) async throws -> NutritionWeeklyCheckInPreview {
        let window = NutritionWeeklyCheckIn.rollingWindow(asOf: asOf)
        let rows = try await buildDayRows(asOf: asOf, window: window, includedOverrides: includedOverrides)
        let density = NutritionWeeklyCheckIn.densityCounts(
            days: rows.map { ($0.hasWeighIn, $0.hasFoodLog, $0.isIncluded) }
        )
        let confidence = NutritionWeeklyCheckIn.confidence(
            weighInDays: density.weighIns,
            foodDays: density.foodDays
        )

        let bodyProfile = resolvedBodyProfile(for: asOf)
        let settings = (try? persistence.trainingPlan.load()) ?? .default
        var currentTrend = trendStore.loadSafely()
        NutritionKit.healTrendState(&currentTrend, bodyProfile: bodyProfile)

        let plannedToday = (try? persistence.plan.fetchPlannedWorkouts(from: asOf, through: asOf)) ?? []
        let hasPlannedSession = plannedToday.contains { $0.status != "skipped" }
        let dayType: NutritionDayType = hasPlannedSession ? .training : .rest
        let currentTargets = NutritionKit.targets(
            for: NutritionTargetContext(bodyProfile: bodyProfile, dayType: dayType),
            phase: settings.phaseGoal,
            trend: currentTrend
        )

        let evidence = try evidenceInputs(asOf: asOf, ritualRows: rows)
        var proposedTrend = currentTrend
        let profileSeed = bodyProfile.flatMap { BodyProfileTDEE.seedTDEEKcal(profile: $0) }
        NutritionKit.reconcileWeekly(
            state: &proposedTrend,
            weekDays: evidence,
            profileSeedTDEEKcal: profileSeed,
            defaultBodyMassKg: bodyProfile?.bodyMassKg ?? NutritionKit.resolvedBodyMassKg(nil)
        )
        NutritionKit.healTrendState(&proposedTrend, bodyProfile: bodyProfile)

        let proposedTargets = NutritionKit.targets(
            for: NutritionTargetContext(bodyProfile: bodyProfile, dayType: dayType),
            phase: settings.phaseGoal,
            trend: proposedTrend
        )

        return NutritionWeeklyCheckInPreview(
            asOf: asOf,
            windowStart: window.start,
            days: rows,
            confidence: confidence,
            weighInDays: density.weighIns,
            foodDays: density.foodDays,
            currentCaloriesKcal: currentTargets.caloriesKcal,
            proposedCaloriesKcal: proposedTargets.caloriesKcal,
            currentProteinGrams: currentTargets.proteinGrams,
            proposedProteinGrams: proposedTargets.proteinGrams,
            currentTDEEKcal: currentTargets.estimatedTDEEKcal,
            proposedTDEEKcal: proposedTargets.estimatedTDEEKcal,
            meetsSoftGate: density.weighIns >= NutritionWeeklyCheckIn.softGateWeighIns
                && density.foodDays >= NutritionWeeklyCheckIn.softGateFoodDays
        )
    }

    @discardableResult
    public func apply(
        asOf: HelmDay,
        includedOverrides: [HelmDay: Bool]
    ) async throws -> NutritionWeeklyCheckInPreview {
        let preview = try await buildPreview(asOf: asOf, includedOverrides: includedOverrides)
        let bodyProfile = resolvedBodyProfile(for: asOf)
        var trend = trendStore.loadSafely()
        NutritionKit.healTrendState(&trend, bodyProfile: bodyProfile)

        let evidence = try evidenceInputs(asOf: asOf, ritualRows: preview.days)
        let profileSeed = bodyProfile.flatMap { BodyProfileTDEE.seedTDEEKcal(profile: $0) }
        NutritionKit.reconcileWeekly(
            state: &trend,
            weekDays: evidence,
            profileSeedTDEEKcal: profileSeed,
            defaultBodyMassKg: bodyProfile?.bodyMassKg ?? NutritionKit.resolvedBodyMassKg(nil)
        )
        NutritionKit.healTrendState(&trend, bodyProfile: bodyProfile)
        try trendStore.save(trend)
        return preview
    }

    private func buildDayRows(
        asOf: HelmDay,
        window: (start: HelmDay, end: HelmDay),
        includedOverrides: [HelmDay: Bool]?
    ) async throws -> [NutritionWeeklyCheckInDayRow] {
        let nutritionDays = try persistence.nutrition.fetchRange(from: window.start, through: window.end)
        let nutritionByDay = Dictionary(uniqueKeysWithValues: nutritionDays.map { ($0.helmDay, $0) })
        let completeDays = try persistence.nutritionLogStatus.completeDays(
            from: window.start,
            through: window.end
        )

        var budgetByDay: [HelmDay: Int] = [:]
        let engine = NutritionEngine(persistence: persistence, calendar: calendar, cutoff: cutoff)
        // Rolling-7 can span two Mon-Sun plan weeks; merge budgets so 80% incomplete works.
        for anchor in [window.start, asOf] {
            if let budget = try? await engine.weeklyBudget(for: anchor, prescriptionSummary: nil) {
                for day in budget.days {
                    budgetByDay[day.day] = day.eatToCaloriesKcal
                }
            }
        }

        var rows: [NutritionWeeklyCheckInDayRow] = []
        var day = window.start
        while day <= window.end {
            let weighIns = try persistence.bodyComposition.fetch(for: day)
            let hasWeighIn = weighIns.contains { $0.mass.kilograms > 1 }
            let meals = try persistence.nutrition.fetchMeals(for: day)
            let stored = nutritionByDay[day]
            let dailyMetrics = try? persistence.dailyMetrics.fetch(helmDay: day)
            let actual = NutritionActualResolver.resolve(
                helmDay: day,
                storedDay: stored,
                dailyMetrics: dailyMetrics,
                meals: meals
            )
            let loggedKcal = actual?.totalEnergy.map { Int($0.kilocalories.rounded()) }
            let hasFoodLog = (loggedKcal ?? 0) > 0 || !meals.isEmpty
            let loggingComplete = completeDays.contains(day)
            let goalKcal = budgetByDay[day]
            let incomplete = NutritionWeeklyCheckIn.isIncomplete(
                loggedKcal: loggedKcal,
                goalKcal: goalKcal,
                loggingComplete: loggingComplete,
                hasFoodLog: hasFoodLog
            )
            let included = includedOverrides?[day]
                ?? NutritionWeeklyCheckIn.defaultIncluded(isIncomplete: incomplete)
            rows.append(
                NutritionWeeklyCheckInDayRow(
                    helmDay: day,
                    hasWeighIn: hasWeighIn,
                    hasFoodLog: hasFoodLog,
                    loggedKcal: loggedKcal,
                    goalKcal: goalKcal,
                    loggingComplete: loggingComplete,
                    isIncomplete: incomplete,
                    isIncluded: included
                )
            )
            day = day.adding(days: 1, calendar: calendar)
        }
        return rows
    }

    /// Engine evidence: 14-day lookback with ritual include/exclude applied to the rolling-7 window.
    private func evidenceInputs(
        asOf: HelmDay,
        ritualRows: [NutritionWeeklyCheckInDayRow]
    ) throws -> [NutritionTrendDayInput] {
        let base = try NutritionTrendBuilder.weekInputs(
            from: persistence,
            endingAt: asOf,
            calendar: calendar
        )
        let ritualByDay = Dictionary(uniqueKeysWithValues: ritualRows.map { ($0.helmDay, $0) })
        return base.map { input in
            guard let ritual = ritualByDay[input.helmDay] else { return input }
            let intake: Double?
            if ritual.isIncluded, let logged = ritual.loggedKcal, logged > 0 {
                intake = Double(logged)
            } else {
                intake = nil
            }
            let mass: Double?
            if ritual.isIncluded, ritual.hasWeighIn {
                mass = input.bodyMassKg
                    ?? (try? persistence.bodyComposition.fetch(for: ritual.helmDay).last?.mass.kilograms)
            } else if ritual.isIncluded {
                mass = input.bodyMassKg
            } else {
                // Excluded ritual day: do not feed that day's weigh-in into EWMA.
                mass = nil
            }
            return NutritionTrendDayInput(
                helmDay: input.helmDay,
                bodyMassKg: mass.flatMap { $0 > 1 ? $0 : nil },
                loggedIntakeKcal: intake
            )
        }
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
}
