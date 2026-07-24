import Core
import Foundation
import HealthKit

public enum HelmHealthKitMetadata {
    public static let mealIDKey = "com.cameronro.helm.meal_id"
    public static let mealNameKey = "com.cameronro.helm.meal_name"
    public static let mealSourceKey = "com.cameronro.helm.meal_source"
    public static let mealSourceHealthKit = "healthKit"
    public static let mealSourceManual = "manual"
    public static let mealSourcePhoto = "photo"
    public static let mealSourceBarcode = "barcode"
    public static let mealSourceQuickAdd = "quickAdd"
    public static let mealSourceAlcohol = "alcohol"
    public static let mealSourceTemplate = "template"

    public static func mealSourceValue(for source: MealRecord.Source) -> String {
        switch source {
        case .healthKit:
            mealSourceHealthKit
        case .manual:
            mealSourceManual
        case .photo:
            mealSourcePhoto
        case .barcode:
            mealSourceBarcode
        case .quickAdd:
            mealSourceQuickAdd
        case .alcohol:
            mealSourceAlcohol
        case .template:
            mealSourceTemplate
        }
    }
}

public struct MealWriteRequest: Sendable {
    public let mealID: String
    public let name: String
    public let loggedAt: Date
    public let caloriesKcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let lineItems: [MealLineItem]
    public let mealSource: String

    public init(
        mealID: String,
        name: String,
        loggedAt: Date,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        lineItems: [MealLineItem] = [],
        mealSource: String = HelmHealthKitMetadata.mealSourcePhoto
    ) {
        self.mealID = mealID
        self.name = name
        self.loggedAt = loggedAt
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.lineItems = lineItems
        self.mealSource = mealSource
    }

    public init(
        estimate: MealEstimate,
        name: String,
        loggedAt: Date,
        mealID: String = UUID().uuidString,
        mealSource: String = HelmHealthKitMetadata.mealSourcePhoto
    ) {
        self.init(
            mealID: mealID,
            name: name,
            loggedAt: loggedAt,
            caloriesKcal: estimate.caloriesKcal,
            proteinG: estimate.proteinG,
            carbsG: estimate.carbsG,
            fatG: estimate.fatG,
            lineItems: estimate.lineItems,
            mealSource: mealSource
        )
    }
}

public struct SavedMealSample: Sendable, Equatable {
    public let id: UUID
    public let sourceBundleID: String?

    public init(id: UUID, sourceBundleID: String?) {
        self.id = id
        self.sourceBundleID = sourceBundleID
    }
}

public struct SavedMealSamples: Sendable, Equatable {
    public let mealID: String
    public let energy: SavedMealSample
    public let protein: SavedMealSample
    public let carbohydrate: SavedMealSample
    public let fat: SavedMealSample

    public init(
        mealID: String,
        energy: SavedMealSample,
        protein: SavedMealSample,
        carbohydrate: SavedMealSample,
        fat: SavedMealSample
    ) {
        self.mealID = mealID
        self.energy = energy
        self.protein = protein
        self.carbohydrate = carbohydrate
        self.fat = fat
    }
}

public protocol MealHealthKitWriting: Sendable {
    func saveMeal(_ request: MealWriteRequest) async throws -> SavedMealSamples
}

public struct MealHealthKitWriter: MealHealthKitWriting {
    private let store: any HealthKitStoreClient

    public init(
        store: any HealthKitStoreClient = LiveHealthKitStore(),
        ownBundleID: String = HealthKitIngest.defaultOwnBundleID
    ) {
        self.store = store
        _ = ownBundleID
    }

    public func saveMeal(_ request: MealWriteRequest) async throws -> SavedMealSamples {
        try await store.saveDietaryMeal(request)
    }
}

extension MealHealthKitWriter {
    public static func shouldReIngest(
        savedMeal: SavedMealSamples,
        ownBundleID: String
    ) -> Bool {
        let samples = [savedMeal.energy, savedMeal.protein, savedMeal.carbohydrate, savedMeal.fat]
        return samples.contains {
            IngestSampleFilter.shouldIngest(sourceBundleID: $0.sourceBundleID, ownBundleID: ownBundleID)
        }
    }
}
