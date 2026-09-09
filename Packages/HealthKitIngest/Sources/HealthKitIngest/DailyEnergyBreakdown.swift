import Core
import Foundation

/// Where a calorie figure in the daily breakdown came from.
public enum EnergyProvenance: String, Sendable, Equatable, Codable {
    case appleHealth
    case healthKitWorkout
    case helmLogged
    case estimated

    public var displayLabel: String {
        switch self {
        case .appleHealth: "Apple Health"
        case .healthKitWorkout: "Apple Fitness"
        case .helmLogged: "Signal workout"
        case .estimated: "Estimated"
        }
    }
}

public struct WorkoutEnergyContributor: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let kilocalories: Int
    public let provenance: EnergyProvenance
    public let detail: String?

    public init(
        id: String,
        title: String,
        kilocalories: Int,
        provenance: EnergyProvenance,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kilocalories = kilocalories
        self.provenance = provenance
        self.detail = detail
    }
}

public enum OtherActivityState: Sendable, Equatable {
    /// Remaining active energy after nested workout contributors reconcile.
    case reconciled(kilocalories: Int)
    /// HealthKit active total is still catching up.
    case syncing
    /// Workout rows sum above the active total; show sync state, not a negative bucket.
    case unreconciled(workoutTotalKcal: Int, activeTotalKcal: Int)
    /// No active energy available for the day.
    case unavailable

    public var isVisible: Bool {
        switch self {
        case .unavailable: false
        case .syncing, .unreconciled, .reconciled: true
        }
    }
}

/// In / out / net energy for one day. Workout burn is nested inside active energy.
public struct DailyEnergyBreakdown: Sendable, Equatable {
    public let intakeKcal: Int?
    public let restingKcal: Int?
    public let activeKcal: Int?
    public let activeFreshness: ActiveEnergyFreshness
    public let workoutContributors: [WorkoutEnergyContributor]
    public let otherActivity: OtherActivityState
    public let totalOutKcal: Int?
    public let netKcal: Int?

    public init(
        intakeKcal: Int?,
        restingKcal: Int?,
        activeKcal: Int?,
        activeFreshness: ActiveEnergyFreshness,
        workoutContributors: [WorkoutEnergyContributor],
        otherActivity: OtherActivityState,
        totalOutKcal: Int?,
        netKcal: Int?
    ) {
        self.intakeKcal = intakeKcal
        self.restingKcal = restingKcal
        self.activeKcal = activeKcal
        self.activeFreshness = activeFreshness
        self.workoutContributors = workoutContributors
        self.otherActivity = otherActivity
        self.totalOutKcal = totalOutKcal
        self.netKcal = netKcal
    }

    public var hasVisibleContent: Bool {
        intakeKcal != nil
            || restingKcal != nil
            || activeKcal != nil
            || !workoutContributors.isEmpty
            || otherActivity.isVisible
    }
}

public enum DailyEnergyBreakdownBuilder {
    public static func build(
        intakeKcal: Int?,
        restingKcal: Double?,
        activeKcal: Int?,
        activeFreshness: ActiveEnergyFreshness,
        workouts: [WorkoutEnergyWorkoutInput],
        bodyMassKilograms: Double?
    ) -> DailyEnergyBreakdown {
        let resting = restingKcal.map { Int($0.rounded()) }
        let contributors = workouts.compactMap { contributor(for: $0, bodyMassKilograms: bodyMassKilograms) }
            .sorted { $0.kilocalories > $1.kilocalories }
        let workoutTotal = contributors.reduce(0) { $0 + $1.kilocalories }

        let otherActivity = resolveOtherActivity(
            activeKcal: activeKcal,
            activeFreshness: activeFreshness,
            workoutTotalKcal: workoutTotal
        )

        // Total out and net require both resting and active; partial components stay visible alone.
        let totalOut: Int?
        if let resting, let activeKcal {
            totalOut = resting + activeKcal
        } else {
            totalOut = nil
        }

        let net: Int?
        if let intakeKcal, let totalOut {
            net = intakeKcal - totalOut
        } else {
            net = nil
        }

        return DailyEnergyBreakdown(
            intakeKcal: intakeKcal,
            restingKcal: resting,
            activeKcal: activeKcal,
            activeFreshness: activeFreshness,
            workoutContributors: contributors,
            otherActivity: otherActivity,
            totalOutKcal: totalOut,
            netKcal: net
        )
    }

    public struct WorkoutEnergyWorkoutInput: Sendable, Equatable {
        public let id: String
        public let title: String?
        public let source: WorkoutSessionSource
        public let startedAt: Date
        public let endedAt: Date?
        public let activityType: String?
        public let activeEnergyKilocalories: Double?

        public init(
            id: String,
            title: String?,
            source: WorkoutSessionSource,
            startedAt: Date,
            endedAt: Date?,
            activityType: String?,
            activeEnergyKilocalories: Double?
        ) {
            self.id = id
            self.title = title
            self.source = source
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.activityType = activityType
            self.activeEnergyKilocalories = activeEnergyKilocalories
        }

        public init(summary: WorkoutSessionSummary) {
            self.init(
                id: summary.id,
                title: summary.title,
                source: summary.source,
                startedAt: summary.startedAt,
                endedAt: summary.endedAt,
                activityType: summary.hkActivityType,
                activeEnergyKilocalories: summary.hkActiveEnergyKilocalories
            )
        }
    }

    private static func contributor(
        for workout: WorkoutEnergyWorkoutInput,
        bodyMassKilograms: Double?
    ) -> WorkoutEnergyContributor? {
        let title = resolvedTitle(for: workout)
        switch workout.source {
        case .healthKit:
            guard let kcal = workout.activeEnergyKilocalories, kcal > 0 else { return nil }
            let activity = workout.activityType ?? title
            return WorkoutEnergyContributor(
                id: workout.id,
                title: title,
                kilocalories: Int(kcal.rounded()),
                provenance: .healthKitWorkout,
                detail: "Apple Fitness · \(activity)"
            )
        case .manual, .template, .prescription, .importSource:
            if let kcal = workout.activeEnergyKilocalories, kcal > 0 {
                return WorkoutEnergyContributor(
                    id: workout.id,
                    title: title,
                    kilocalories: Int(kcal.rounded()),
                    provenance: .helmLogged,
                    detail: EnergyProvenance.helmLogged.displayLabel
                )
            }
            guard let endedAt = workout.endedAt else { return nil }
            let estimated = StrengthWorkoutEnergyEstimator.activeEnergyKilocalories(
                startedAt: workout.startedAt,
                endedAt: endedAt,
                bodyMassKilograms: bodyMassKilograms
            )
            guard estimated > 0 else { return nil }
            return WorkoutEnergyContributor(
                id: workout.id,
                title: title,
                kilocalories: Int(estimated.rounded()),
                provenance: .estimated,
                detail: "Estimated from session duration"
            )
        }
    }

    private static func resolvedTitle(for workout: WorkoutEnergyWorkoutInput) -> String {
        if let title = workout.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let activity = workout.activityType?.trimmingCharacters(in: .whitespacesAndNewlines), !activity.isEmpty {
            return activity
        }
        switch workout.source {
        case .healthKit: return "Workout"
        default: return "Strength session"
        }
    }

    static func resolveOtherActivity(
        activeKcal: Int?,
        activeFreshness: ActiveEnergyFreshness,
        workoutTotalKcal: Int
    ) -> OtherActivityState {
        switch activeFreshness {
        case .unavailable:
            return .unavailable
        case let .stale(partial):
            if partial == nil {
                return .syncing
            }
            guard let activeKcal else { return .syncing }
            return reconcile(activeKcal: activeKcal, workoutTotalKcal: workoutTotalKcal)
        case .fresh:
            guard let activeKcal else { return .unavailable }
            return reconcile(activeKcal: activeKcal, workoutTotalKcal: workoutTotalKcal)
        }
    }

    private static func reconcile(activeKcal: Int, workoutTotalKcal: Int) -> OtherActivityState {
        if workoutTotalKcal > activeKcal {
            return .unreconciled(workoutTotalKcal: workoutTotalKcal, activeTotalKcal: activeKcal)
        }
        return .reconciled(kilocalories: max(0, activeKcal - workoutTotalKcal))
    }
}
