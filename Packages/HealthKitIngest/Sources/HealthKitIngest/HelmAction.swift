import CoachLLM
import Core
import Foundation
import Persistence

/// Domain command shared by Coach confirm paths and UI persist-after-confirm.
public enum HelmActionCommand: Sendable {
    case meal(HelmMealWrite)
    case copyMeal(HelmCopyMealCommand)
    case copyAllMeals(sourceDay: HelmDay, targetDay: HelmDay)
    case applySessionAdjustment(HelmSessionAdjustmentCommand)
}

public enum HelmMealWrite: Sendable {
    case fromCoachPayload(FoodLogPayload, now: Date)
    case logFood(
        product: ResolvedFoodProduct,
        grams: Double,
        servingLabel: String?,
        bucket: MealBucket,
        loggedAt: Date,
        helmDay: HelmDay,
        source: MealRecord.Source
    )
    case logQuickAdd(
        kilocalories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        label: String?,
        bucket: MealBucket,
        loggedAt: Date,
        helmDay: HelmDay,
        mealID: String
    )
    case logAlcohol(
        preset: AlcoholDrinkPreset,
        quantity: Int,
        bucket: MealBucket,
        loggedAt: Date,
        helmDay: HelmDay
    )
    case logComposite(
        name: String,
        bucket: MealBucket,
        lineItems: [MealLineItemRecord],
        loggedAt: Date,
        helmDay: HelmDay,
        mealID: String,
        source: MealRecord.Source
    )
    case updateMeal(
        mealID: UUID,
        name: String,
        bucket: MealBucket,
        loggedAt: Date,
        macros: FoodPortionMacros,
        lineItems: [MealLineItemRecord],
        source: MealRecord.Source,
        helmDay: HelmDay
    )
    case deleteMeal(mealID: UUID, helmDay: HelmDay)
}

public struct HelmCopyMealCommand: Sendable, Equatable {
    public let sourceDay: HelmDay
    public let sourceBucket: MealBucket
    public let targetDay: HelmDay
    public let targetBucket: MealBucket?

    public init(
        sourceDay: HelmDay,
        sourceBucket: MealBucket,
        targetDay: HelmDay,
        targetBucket: MealBucket? = nil
    ) {
        self.sourceDay = sourceDay
        self.sourceBucket = sourceBucket
        self.targetDay = targetDay
        self.targetBucket = targetBucket
    }
}

public struct HelmSessionAdjustmentCommand: Sendable {
    public let payload: SessionAdjustmentPayload
    public let snapshot: ActiveSessionSnapshot
    public let excludedExerciseIDs: Set<String>
    public let userMessage: String?
    public let modelVersion: String?
    public let recommendationID: String?
    public let markActedOn: Bool

    public init(
        payload: SessionAdjustmentPayload,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        userMessage: String? = nil,
        modelVersion: String? = nil,
        recommendationID: String? = nil,
        markActedOn: Bool = true
    ) {
        self.payload = payload
        self.snapshot = snapshot
        self.excludedExerciseIDs = excludedExerciseIDs
        self.userMessage = userMessage
        self.modelVersion = modelVersion
        self.recommendationID = recommendationID
        self.markActedOn = markActedOn
    }
}

public enum HelmActionSideEffect: Sendable, Equatable {
    case refreshNutrition(HelmDay)
    case refreshPrescription
}

public struct HelmActionResult: Sendable, Equatable {
    public let nutritionDay: HelmDay?
    public let sessionAdjustment: AppliedSessionAdjustment?
    public let sideEffects: [HelmActionSideEffect]

    public init(
        nutritionDay: HelmDay? = nil,
        sessionAdjustment: AppliedSessionAdjustment? = nil,
        sideEffects: [HelmActionSideEffect] = []
    ) {
        self.nutritionDay = nutritionDay
        self.sessionAdjustment = sessionAdjustment
        self.sideEffects = sideEffects
    }

    public static func nutrition(_ day: HelmDay) -> HelmActionResult {
        HelmActionResult(
            nutritionDay: day,
            sideEffects: [.refreshNutrition(day)]
        )
    }
}
