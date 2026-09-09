import CoachLLM
import Core
import Foundation
import Persistence

public enum FoodLogProposalValidationError: Sendable, Equatable {
    case missingMealQuery
    case missingMealID
    case mealNotFound
    case staleMealQuery
    case mealIDNotInQuery

    public var recoveryMessage: String {
        switch self {
        case .missingMealQuery:
            return "I need to look up that meal in your diary first. Tell me the day and meal (for example, Sunday dinner), then I can edit or delete it."
        case .missingMealID:
            return "I need the exact meal entry from your diary before I can change it. Ask me what was logged on that day, then tell me which item to update or remove."
        case .mealNotFound:
            return "That meal is not in your diary anymore. Ask me to list what is logged on that day and pick the entry to change."
        case .staleMealQuery:
            return "That diary lookup is stale. Ask me again what was logged on that day, then I can edit or delete the right entry."
        case .mealIDNotInQuery:
            return "That meal ID does not match the diary entries I just looked up. Ask me to list that day again, then pick the item to change."
        }
    }
}

public enum FoodLogProposalValidator {
    public static func validate(
        payload: FoodLogPayload,
        queryContext: MealQueryContext?,
        persistence: PersistenceStore,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> FoodLogProposalValidationError? {
        switch payload.action {
        case .log:
            return nil
        case .edit:
            return validateMutation(
                payload: payload,
                queryContext: queryContext,
                persistence: persistence,
                now: now,
                calendar: calendar,
                requiresMealID: true
            )
        case .delete:
            if payload.mealID != nil {
                return validateMutation(
                    payload: payload,
                    queryContext: queryContext,
                    persistence: persistence,
                    now: now,
                    calendar: calendar,
                    requiresMealID: true
                )
            }
            return validateBulkDelete(
                payload: payload,
                queryContext: queryContext,
                now: now,
                calendar: calendar
            )
        }
    }

    private static func validateMutation(
        payload: FoodLogPayload,
        queryContext: MealQueryContext?,
        persistence: PersistenceStore,
        now: Date,
        calendar: Calendar,
        requiresMealID: Bool
    ) -> FoodLogProposalValidationError? {
        guard let queryContext else {
            return .missingMealQuery
        }
        guard queryContext.isFresh(at: now) else {
            return .staleMealQuery
        }
        guard let mealIDString = payload.mealID,
              let mealID = UUID(uuidString: mealIDString) else {
            return requiresMealID ? .missingMealID : nil
        }
        guard queryContext.mealIDs.contains(mealID) else {
            if (try? persistence.nutrition.fetchMeal(id: mealID)) != nil {
                return .mealIDNotInQuery
            }
            return .mealNotFound
        }
        return nil
    }

    private static func validateBulkDelete(
        payload: FoodLogPayload,
        queryContext: MealQueryContext?,
        now: Date,
        calendar: Calendar
    ) -> FoodLogProposalValidationError? {
        guard let queryContext, queryContext.isFresh(at: now) else {
            return .missingMealQuery
        }
        guard let dayRaw = payload.helmDay,
              let helmDay = parseDay(dayRaw) else {
            return .missingMealID
        }
        if let queryDay = queryContext.helmDay, queryDay != helmDay {
            return .mealIDNotInQuery
        }
        if let bucketRaw = payload.bucket,
           let bucket = MealBucket(rawValue: bucketRaw.lowercased()),
           let queryBucket = queryContext.bucket,
           queryBucket != bucket {
            return .mealIDNotInQuery
        }
        return nil
    }

    private static func parseDay(_ raw: String) -> HelmDay? {
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
