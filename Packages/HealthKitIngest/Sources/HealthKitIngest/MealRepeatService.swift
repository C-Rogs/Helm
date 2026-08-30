import Core
import Foundation
import Persistence

public enum MealRepeatError: Error, Sendable, Equatable {
    case emptySource
    case emptyBucket
}

/// Copy meals between days, save templates, and log saved templates.
public struct MealRepeatService: Sendable {
    private let nutrition: NutritionRepository
    private let foodLog: FoodLogRepository
    private let mealTemplates: MealTemplateRepository
    private let manualMealService: ManualMealService
    private let now: @Sendable () -> Date

    public init(
        store: PersistenceStore,
        manualMealService: ManualMealService,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        nutrition = store.nutrition
        foodLog = store.foodLog
        mealTemplates = store.mealTemplates
        self.manualMealService = manualMealService
        self.now = now
    }

    public func fetchTemplates() throws -> [MealTemplate] {
        try mealTemplates.fetchAll()
    }

    public func saveTemplate(_ template: MealTemplate) throws {
        try mealTemplates.save(template)
    }

    public func deleteTemplate(id: UUID) throws {
        try mealTemplates.delete(id: id)
    }

    public func buildTemplate(
        name: String,
        bucket: MealBucket,
        helmDay: HelmDay,
        updatedAt: Date? = nil
    ) throws -> MealTemplate? {
        let meals = try nutrition.fetchMeals(for: helmDay)
            .filter { $0.bucket == bucket }
        guard !meals.isEmpty else { return nil }

        var lineItems: [MealLineItem] = []
        for meal in meals {
            let records = try foodLog.fetchLineItems(for: meal.id)
            if records.isEmpty {
                lineItems.append(
                    MealLineItem(
                        name: meal.name,
                        grams: 0,
                        caloriesKcal: meal.energy?.kilocalories ?? 0,
                        proteinG: meal.proteinGrams ?? 0,
                        carbsG: meal.carbohydrateGrams ?? 0,
                        fatG: meal.fatGrams ?? 0,
                        matchConfidence: .medium
                    )
                )
            } else {
                lineItems.append(contentsOf: records.map(MealLineItemTemplateMapping.lineItem(from:)))
            }
        }
        guard !lineItems.isEmpty else { return nil }

        return MealTemplate(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            bucket: bucket,
            lineItems: lineItems,
            updatedAt: updatedAt ?? now()
        )
    }

    @discardableResult
    public func logTemplate(
        _ template: MealTemplate,
        loggedAt: Date? = nil,
        helmDay: HelmDay? = nil
    ) async throws -> SavedMealSamples {
        let timestamp = loggedAt ?? now()
        let mealID = UUID()
        let records = template.lineItems.enumerated().map { index, item in
            MealLineItemTemplateMapping.record(from: item, mealID: mealID, sortOrder: index)
        }
        return try await manualMealService.logCompositeMeal(
            name: template.name,
            bucket: template.bucket,
            lineItems: records,
            loggedAt: timestamp,
            helmDay: helmDay,
            mealID: mealID.uuidString,
            source: .template
        )
    }

    @discardableResult
    public func copyBucket(
        from sourceDay: HelmDay,
        bucket: MealBucket,
        to targetDay: HelmDay,
        targetBucket: MealBucket? = nil,
        loggedAt: Date? = nil
    ) async throws -> Int {
        let meals = try nutrition.fetchMeals(for: sourceDay)
            .filter { $0.bucket == bucket }
        guard !meals.isEmpty else { throw MealRepeatError.emptyBucket }
        let destinationBucket = targetBucket ?? bucket
        return try await copy(
            meals: meals,
            to: targetDay,
            targetBucket: destinationBucket,
            loggedAt: loggedAt
        )
    }

    @discardableResult
    public func copyAllMeals(
        from sourceDay: HelmDay,
        to targetDay: HelmDay,
        loggedAt: Date? = nil
    ) async throws -> Int {
        let meals = try nutrition.fetchMeals(for: sourceDay)
        guard !meals.isEmpty else { throw MealRepeatError.emptySource }
        return try await copy(
            meals: meals,
            to: targetDay,
            targetBucket: nil,
            loggedAt: loggedAt
        )
    }

    private func copy(
        meals: [MealRecord],
        to targetDay: HelmDay,
        targetBucket: MealBucket?,
        loggedAt: Date?
    ) async throws -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let baseStart = targetDay.startInstant(calendar: calendar) ?? loggedAt ?? now()
        var copiedCount = 0

        for (index, meal) in meals.enumerated() {
            let mealID = UUID()
            let timestamp = baseStart.addingTimeInterval(Double(index * 60) + 3_600)
            let bucket = targetBucket ?? meal.bucket
            let records = try foodLog.fetchLineItems(for: meal.id)
            if records.isEmpty {
                _ = try await manualMealService.logCompositeMeal(
                    name: meal.name,
                    bucket: bucket,
                    lineItems: [],
                    loggedAt: timestamp,
                    helmDay: targetDay,
                    mealID: mealID.uuidString,
                    source: meal.source,
                    overrideMacros: FoodPortionMacros(
                        energyKcal: meal.energy?.kilocalories ?? 0,
                        proteinG: meal.proteinGrams ?? 0,
                        carbsG: meal.carbohydrateGrams ?? 0,
                        fatG: meal.fatGrams ?? 0
                    )
                )
            } else {
                let copiedRecords = records.enumerated().map { itemIndex, record in
                    MealLineItemRecord(
                        mealID: mealID,
                        foodRef: record.foodRef,
                        grams: record.grams,
                        servingLabel: record.servingLabel,
                        energyKcal: record.energyKcal,
                        proteinG: record.proteinG,
                        carbsG: record.carbsG,
                        fatG: record.fatG,
                        sortOrder: itemIndex
                    )
                }
                _ = try await manualMealService.logCompositeMeal(
                    name: meal.name,
                    bucket: bucket,
                    lineItems: copiedRecords,
                    loggedAt: timestamp,
                    helmDay: targetDay,
                    mealID: mealID.uuidString,
                    source: meal.source
                )
            }
            copiedCount += 1
        }

        return copiedCount
    }
}
