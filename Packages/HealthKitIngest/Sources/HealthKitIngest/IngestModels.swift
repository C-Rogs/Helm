import Core
import Foundation

/// Portable quantity sample used by ingest logic and fixture tests.
public struct IngestQuantitySample: Sendable, Hashable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let value: Double
    public let unitSymbol: String
    public let sourceBundleID: String?

    public init(
        id: UUID,
        start: Date,
        end: Date,
        value: Double,
        unitSymbol: String,
        sourceBundleID: String?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.value = value
        self.unitSymbol = unitSymbol
        self.sourceBundleID = sourceBundleID
    }
}

public struct IngestSleepSample: Sendable, Hashable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let stage: SleepAnalysisStage
    public let sourceBundleID: String?

    public init(
        id: UUID,
        start: Date,
        end: Date,
        stage: SleepAnalysisStage,
        sourceBundleID: String?
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceBundleID = sourceBundleID
    }

    public var isAsleep: Bool { stage.isAsleep }
}

public struct IngestWorkoutSample: Sendable, Hashable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let sourceBundleID: String?
    /// `HKWorkoutActivityType` raw value (UInt). Nil for pre-enrichment callers.
    public let activityTypeRawValue: UInt?
    /// Apple display name for the activity type. Nil for pre-enrichment callers.
    public let activityDisplayName: String?
    /// Active energy burned, in kilocalories. Nil when unavailable.
    public let activeEnergyKilocalories: Double?
    /// Total distance in meters. Nil when unavailable.
    public let totalDistanceMeters: Double?

    public init(
        id: UUID,
        start: Date,
        end: Date,
        sourceBundleID: String?,
        activityTypeRawValue: UInt? = nil,
        activityDisplayName: String? = nil,
        activeEnergyKilocalories: Double? = nil,
        totalDistanceMeters: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceBundleID = sourceBundleID
        self.activityTypeRawValue = activityTypeRawValue
        self.activityDisplayName = activityDisplayName
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.totalDistanceMeters = totalDistanceMeters
    }
}

public struct AggregatedDailyPatch: Sendable, Equatable {
    public let helmDay: HelmDay
    public var hrvSDNN: DurationMs?
    public var restingHeartRate: Int?
    public var respiratoryRate: Double?
    public var wristTemperatureDeltaCelsius: Double?
    public var activeEnergy: Energy?
    public var dietaryEnergy: Energy?
    public var dietaryProteinGrams: Double?
    public var dietaryCarbohydrateGrams: Double?
    public var dietaryFatGrams: Double?
    public var stepCount: Int?
    public var restingEnergyKcal: Double?

    public init(helmDay: HelmDay) {
        self.helmDay = helmDay
    }
}

public struct IngestMealDraft: Sendable, Hashable {
    public let id: UUID
    public let helmDay: HelmDay
    public let loggedAt: Date
    public let energy: Energy?
    public let proteinGrams: Double?
    public let carbohydrateGrams: Double?
    public let fatGrams: Double?
    public let externalSampleID: String

    public init(
        id: UUID,
        helmDay: HelmDay,
        loggedAt: Date,
        energy: Energy?,
        proteinGrams: Double?,
        carbohydrateGrams: Double?,
        fatGrams: Double?,
        externalSampleID: String
    ) {
        self.id = id
        self.helmDay = helmDay
        self.loggedAt = loggedAt
        self.energy = energy
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.externalSampleID = externalSampleID
    }
}

public struct IngestDelta: Sendable {
    public let kind: HealthKitSampleKind
    public let addedQuantitySamples: [IngestQuantitySample]
    public let addedSleepSamples: [IngestSleepSample]
    public let addedWorkouts: [IngestWorkoutSample]
    public let deletedSampleIDs: [UUID]
    /// Edwards TRIMP to merge into `prior_day_trimp` on each target logical day.
    public let trimpByTargetDay: [HelmDay: Double]

    public init(
        kind: HealthKitSampleKind,
        addedQuantitySamples: [IngestQuantitySample] = [],
        addedSleepSamples: [IngestSleepSample] = [],
        addedWorkouts: [IngestWorkoutSample] = [],
        deletedSampleIDs: [UUID] = [],
        trimpByTargetDay: [HelmDay: Double] = [:]
    ) {
        self.kind = kind
        self.addedQuantitySamples = addedQuantitySamples
        self.addedSleepSamples = addedSleepSamples
        self.addedWorkouts = addedWorkouts
        self.deletedSampleIDs = deletedSampleIDs
        self.trimpByTargetDay = trimpByTargetDay
    }
}
