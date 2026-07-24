import Foundation

/// One logged meal within a logical day.
public struct MealRecord: Sendable, Hashable, Codable, Identifiable {
    public enum Source: String, Sendable, Codable, CaseIterable {
        case healthKit
        case manual
        case photo
        case barcode
        case quickAdd
        case alcohol
        case template
    }

    public let id: UUID
    public let helmDay: HelmDay
    public let name: String
    public let loggedAt: Date
    public let bucket: MealBucket
    public let energy: Energy?
    public let proteinGrams: Double?
    public let carbohydrateGrams: Double?
    public let fatGrams: Double?
    public let source: Source
    /// HealthKit sample UUID for idempotent ingest; nil for Helm-native entries until written back.
    public let externalSampleID: String?

    public init(
        id: UUID = UUID(),
        helmDay: HelmDay,
        name: String,
        loggedAt: Date,
        bucket: MealBucket = .snacks,
        energy: Energy? = nil,
        proteinGrams: Double? = nil,
        carbohydrateGrams: Double? = nil,
        fatGrams: Double? = nil,
        source: Source,
        externalSampleID: String? = nil
    ) {
        self.id = id
        self.helmDay = helmDay
        self.name = name
        self.loggedAt = loggedAt
        self.bucket = bucket
        self.energy = energy
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.source = source
        self.externalSampleID = externalSampleID
    }
}
