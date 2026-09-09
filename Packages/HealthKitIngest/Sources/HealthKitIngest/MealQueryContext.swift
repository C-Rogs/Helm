import CoachLLM
import Core
import Foundation
import Persistence

/// Parsed meal_query follow-up context used to gate edit/delete proposals.
public struct MealQueryContext: Sendable, Equatable {
    public let queriedAt: Date
    public let helmDay: HelmDay?
    public let bucket: MealBucket?
    public let mealIDs: Set<UUID>

    public init(
        queriedAt: Date = .now,
        helmDay: HelmDay?,
        bucket: MealBucket?,
        mealIDs: Set<UUID>
    ) {
        self.queriedAt = queriedAt
        self.helmDay = helmDay
        self.bucket = bucket
        self.mealIDs = mealIDs
    }

    public static func from(
        query: MealQueryPayload,
        results: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> MealQueryContext {
        let today = HelmDay.day(for: now, calendar: calendar)
        let helmDay = parseDay(query.helmDay) ?? today
        let bucket = query.bucket.flatMap { MealBucket(rawValue: $0.lowercased()) }
        let mealIDs = parseMealIDs(from: results)
        return MealQueryContext(
            queriedAt: now,
            helmDay: helmDay,
            bucket: bucket,
            mealIDs: mealIDs
        )
    }

    public func isFresh(at now: Date = .now, maxAge: TimeInterval = 15 * 60) -> Bool {
        now.timeIntervalSince(queriedAt) <= maxAge
    }

    private static func parseDay(_ raw: String?) -> HelmDay? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

    private static func parseMealIDs(from results: String) -> Set<UUID> {
        var ids: Set<UUID> = []
        for line in results.split(separator: "\n") {
            guard let rawID = line.split(separator: " ")
                .first(where: { $0.hasPrefix("id=") })
                .map(String.init)?
                .dropFirst(3),
                let uuid = UUID(uuidString: String(rawID)) else {
                continue
            }
            ids.insert(uuid)
        }
        return ids
    }
}
