import CoachLLM
import Core
import Foundation
import Persistence

/// Single persist implementation for meal writes, meal copy, and in-session PlanKit adjusts.
public struct HelmActionExecutor: Sendable {
    private let manualMealService: ManualMealService
    private let persistence: PersistenceStore
    private let mealRepeatService: MealRepeatService
    private let photoPersister: PhotoMealPersister
    private let calendar: Calendar

    public init(
        manualMealService: ManualMealService,
        persistence: PersistenceStore,
        mealRepeatService: MealRepeatService,
        calendar: Calendar = .current,
        photoPersister: PhotoMealPersister? = nil
    ) {
        self.manualMealService = manualMealService
        self.persistence = persistence
        self.mealRepeatService = mealRepeatService
        self.calendar = calendar
        self.photoPersister = photoPersister ?? PhotoMealPersister(
            localStore: PhotoMealLocalStore(store: persistence, calendar: calendar)
        )
    }

    public init(persistence: PersistenceStore, calendar: Calendar = .current) {
        let meals = ManualMealService(
            localStore: ManualMealLocalStore(store: persistence, calendar: calendar)
        )
        self.init(
            manualMealService: meals,
            persistence: persistence,
            mealRepeatService: MealRepeatService(store: persistence, manualMealService: meals),
            calendar: calendar
        )
    }

    public func run(_ command: HelmActionCommand) async throws -> HelmActionResult {
        switch command {
        case let .meal(write):
            return try await runMeal(write)
        case let .copyMeal(copy):
            _ = try await mealRepeatService.copyBucket(
                from: copy.sourceDay,
                bucket: copy.sourceBucket,
                to: copy.targetDay,
                targetBucket: copy.targetBucket
            )
            return .nutrition(copy.targetDay)
        case let .copyAllMeals(sourceDay, targetDay):
            _ = try await mealRepeatService.copyAllMeals(from: sourceDay, to: targetDay)
            return .nutrition(targetDay)
        case let .logTemplate(template, loggedAt, helmDay):
            let timestamp = loggedAt ?? Date()
            _ = try await mealRepeatService.logTemplate(
                template,
                loggedAt: timestamp,
                helmDay: helmDay
            )
            return .nutrition(helmDay ?? HelmDay.day(for: timestamp, calendar: calendar))
        case let .applySessionAdjustment(session):
            let applied = try applySessionAdjustment(session)
            return HelmActionResult(
                sessionAdjustment: applied,
                sideEffects: [.refreshPrescription]
            )
        }
    }

    public func applySessionAdjustment(
        _ command: HelmSessionAdjustmentCommand
    ) throws -> AppliedSessionAdjustment {
        try InSessionCoachService(persistence: persistence).applyAdjustment(
            payload: command.payload,
            snapshot: command.snapshot,
            excludedExerciseIDs: command.excludedExerciseIDs,
            userMessage: command.userMessage,
            modelVersion: command.modelVersion,
            recommendationID: command.recommendationID,
            markActedOn: command.markActedOn
        )
    }

    private func runMeal(_ write: HelmMealWrite) async throws -> HelmActionResult {
        switch write {
        case let .fromCoachPayload(payload, payloadNow):
            let applier = FoodLogCommandApplier(
                manualMealService: manualMealService,
                persistence: persistence,
                calendar: calendar
            )
            try await applier.apply(payload, now: payloadNow)
            let day = FoodLogCommandApplier.resolvedHelmDay(
                from: payload,
                now: payloadNow,
                calendar: calendar
            )
            return .nutrition(day)

        case let .logFood(product, grams, servingLabel, bucket, loggedAt, helmDay, source):
            _ = try await manualMealService.logFood(
                product: product,
                grams: grams,
                servingLabel: servingLabel,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: helmDay,
                source: source
            )
            return .nutrition(helmDay)

        case let .logQuickAdd(
            kilocalories, proteinG, carbsG, fatG, label, bucket, loggedAt, helmDay, mealID
        ):
            _ = try await manualMealService.logQuickAdd(
                kilocalories: kilocalories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                label: label,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: helmDay,
                mealID: mealID
            )
            return .nutrition(helmDay)

        case let .logAlcohol(preset, quantity, bucket, loggedAt, helmDay):
            _ = try await manualMealService.logAlcohol(
                preset: preset,
                quantity: quantity,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: helmDay
            )
            return .nutrition(helmDay)

        case let .logComposite(name, bucket, lineItems, loggedAt, helmDay, mealID, source):
            _ = try await manualMealService.logCompositeMeal(
                name: name,
                bucket: bucket,
                lineItems: lineItems,
                loggedAt: loggedAt,
                helmDay: helmDay,
                mealID: mealID,
                source: source
            )
            return .nutrition(helmDay)

        case let .updateMeal(mealID, name, bucket, loggedAt, macros, lineItems, source, helmDay):
            _ = try await manualMealService.updateMeal(
                mealID: mealID,
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                macros: macros,
                lineItems: lineItems,
                source: source
            )
            return .nutrition(helmDay)

        case let .deleteMeal(mealID, helmDay):
            try await manualMealService.deleteMeal(mealID: mealID)
            return .nutrition(helmDay)

        case let .logPhoto(estimate, name, bucket, loggedAt, helmDay, mealID):
            _ = try await photoPersister.confirm(
                estimate: estimate,
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: helmDay,
                mealID: mealID
            )
            return .nutrition(helmDay)
        }
    }
}
