import CoachLLM
import Core
import Foundation
import Persistence

public enum FoodLogPayloadParser {
    public static func parse(from text: String) -> FoodLogPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .foodLogV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(FoodLogPayload.self, from: data)
        else {
            return nil
        }
        return payload
    }

    /// True when a food_log.v1 block is present but cannot be decoded into a payload.
    public static func hasMalformedBlock(in text: String) -> Bool {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .foodLogV1),
              let data = block.data(using: .utf8)
        else {
            return false
        }
        return (try? JSONDecoder().decode(FoodLogPayload.self, from: data)) == nil
    }
}

public enum FoodLogCommandPreview {
    public static func preview(for payload: FoodLogPayload) -> (title: String, detail: String) {
        switch payload.action {
        case .log:
            let bucket = displayBucket(payload.bucket)
            let description = payload.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let kcal = payload.caloriesKcal.map { Int($0.rounded()) }
            var detailParts: [String] = []
            if let description, !description.isEmpty {
                detailParts.append(description)
            }
            if let kcal {
                detailParts.append("\(kcal) kcal")
            }
            return (
                title: "Log \(bucket.lowercased())",
                detail: detailParts.isEmpty ? "Quick meal entry" : detailParts.joined(separator: " · ")
            )
        case .edit:
            return (title: "Update meal", detail: payload.description ?? "Edit logged meal")
        case .delete:
            if payload.mealID == nil, payload.helmDay != nil {
                let day = payload.helmDay ?? "day"
                let bucket = payload.bucket.map { displayBucket($0) }
                if let bucket {
                    return (title: "Delete \(bucket.lowercased())", detail: day)
                }
                return (title: "Delete day's meals", detail: day)
            }
            return (title: "Delete meal", detail: payload.description ?? "Remove from diary")
        }
    }

    private static func displayBucket(_ raw: String?) -> String {
        guard let raw else { return "Meal" }
        return MealBucket(rawValue: raw.lowercased())?.displayName ?? raw.capitalized
    }
}

public struct FoodLogCommandApplier: Sendable {
    private let manualMealService: ManualMealService
    private let persistence: PersistenceStore
    private let calendar: Calendar

    public init(
        manualMealService: ManualMealService,
        persistence: PersistenceStore,
        calendar: Calendar = .current
    ) {
        self.manualMealService = manualMealService
        self.persistence = persistence
        self.calendar = calendar
    }

    public func apply(_ payload: FoodLogPayload, now: Date = Date()) async throws {
        switch payload.action {
        case .log:
            try await applyLog(payload, now: now)
        case .edit:
            try await applyEdit(payload, now: now)
        case .delete:
            try await applyDelete(payload, now: now)
        }
    }

    private func applyLog(_ payload: FoodLogPayload, now: Date) async throws {
        let bucket = resolvedBucket(payload.bucket)
        let helmDay = resolvedHelmDay(payload.helmDay, now: now)
        let kilocalories = payload.caloriesKcal ?? 0
        guard kilocalories > 0 else {
            throw ManualMealError.invalidQuickAdd
        }

        _ = try await manualMealService.logQuickAdd(
            kilocalories: kilocalories,
            proteinG: payload.proteinG ?? 0,
            carbsG: payload.carbsG ?? 0,
            fatG: payload.fatG ?? 0,
            label: payload.description,
            bucket: bucket,
            loggedAt: loggedAt(for: helmDay, now: now),
            helmDay: helmDay
        )
    }

    private func loggedAt(for helmDay: HelmDay, now: Date) -> Date {
        let today = HelmDay.day(for: now, calendar: calendar)
        if helmDay == today {
            return now
        }
        if let start = helmDay.startInstant(calendar: calendar) {
            return start.addingTimeInterval(3_600)
        }
        return now
    }

    private func applyEdit(_ payload: FoodLogPayload, now: Date) async throws {
        guard let mealIDString = payload.mealID,
              let mealID = UUID(uuidString: mealIDString) else {
            throw ManualMealError.mealNotFound
        }
        try await manualMealService.deleteMeal(mealID: mealID)
        try await applyLog(payload, now: now)
    }

    private func applyDelete(_ payload: FoodLogPayload, now: Date = Date()) async throws {
        if let mealIDString = payload.mealID,
           let mealID = UUID(uuidString: mealIDString) {
            try await manualMealService.deleteMeal(mealID: mealID)
            return
        }

        // Bulk delete: helmDay required (optional bucket filter).
        guard let dayRaw = payload.helmDay,
              let helmDay = HelmDayParser.parse(dayRaw) else {
            throw ManualMealError.mealNotFound
        }

        var meals = try persistence.nutrition.fetchMeals(for: helmDay)
        if let bucketRaw = payload.bucket,
           let bucket = MealBucket(rawValue: bucketRaw.lowercased()) {
            meals = meals.filter { $0.bucket == bucket }
        }
        guard !meals.isEmpty else {
            throw ManualMealError.nothingToDelete
        }

        for meal in meals {
            try await manualMealService.deleteMeal(mealID: meal.id)
        }
    }

    private func resolvedBucket(_ raw: String?) -> MealBucket {
        guard let raw else { return .snacks }
        return MealBucket(rawValue: raw.lowercased()) ?? .snacks
    }

    private func resolvedHelmDay(_ raw: String?, now: Date) -> HelmDay {
        if let raw,
           let parsed = HelmDayParser.parse(raw) {
            return parsed
        }
        return HelmDay.day(for: now, calendar: calendar)
    }

    public static func resolvedHelmDay(
        from payload: FoodLogPayload,
        now: Date,
        calendar: Calendar = .current
    ) -> HelmDay {
        if let raw = payload.helmDay,
           let parsed = HelmDayParser.parse(raw) {
            return parsed
        }
        return HelmDay.day(for: now, calendar: calendar)
    }
}

private enum HelmDayParser {
    static func parse(_ raw: String) -> HelmDay? {
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
