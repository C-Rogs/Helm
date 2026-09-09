import CoachLLM
import Core
import Foundation
import Persistence

/// Prevents duplicate coach mutations when the athlete retries a confirm card.
public struct CoachMutationLedger: Sendable {
    private struct Entry: Codable, Equatable {
        var key: String
        var appliedAt: Date
    }

    private let metadata: AppMetadataStore
    private static let storageKey = "helm.coach.mutationKeys"
    private static let maxEntries = 200
    private static let ttl: TimeInterval = 7 * 24 * 3_600

    public init(metadata: AppMetadataStore) {
        self.metadata = metadata
    }

    public func wasApplied(_ key: String) -> Bool {
        loadEntries().contains { $0.key == key && !isExpired($0) }
    }

    public func recordApplied(_ key: String, at date: Date = .now) throws {
        var entries = loadEntries().filter { !isExpired($0) && $0.key != key }
        entries.append(Entry(key: key, appliedAt: date))
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
        let data = try JSONEncoder().encode(entries)
        let json = String(decoding: data, as: UTF8.self)
        try metadata.setValue(json, forKey: Self.storageKey)
    }

    private func loadEntries() -> [Entry] {
        guard let json = try? metadata.value(forKey: Self.storageKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func isExpired(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.appliedAt) > Self.ttl
    }
}

public enum CoachMutationIdempotency {
    public static func key(
        forFoodLog payload: FoodLogPayload,
        resolvedHelmDay: HelmDay
    ) -> String {
        let mealID = payload.mealID ?? "bulk"
        let bucket = payload.bucket ?? "any"
        return [
            "food_log",
            payload.action.rawValue,
            resolvedHelmDay.formatted,
            bucket.lowercased(),
            mealID.lowercased(),
            macroFingerprint(payload)
        ].joined(separator: "|")
    }

    public static func key(forMealCopy command: HelmCopyMealCommand) -> String {
        let targetBucket = command.targetBucket ?? command.sourceBucket
        return [
            "meal_copy",
            command.sourceDay.formatted,
            command.sourceBucket.rawValue,
            command.targetDay.formatted,
            targetBucket.rawValue
        ].joined(separator: "|")
    }

    public static func key(
        forSession proposal: CoachSessionProposal,
        sessionID: String
    ) -> String {
        let operations = proposal.payload.operations
            .map {
                "\($0.kind.rawValue):\($0.fromExerciseID ?? ""):\($0.toExerciseID ?? ""):\($0.exerciseID ?? "")"
            }
            .joined(separator: ";")
        return [
            "session_adjust",
            sessionID,
            proposal.recommendationID,
            operations
        ].joined(separator: "|")
    }

    private static func macroFingerprint(_ payload: FoodLogPayload) -> String {
        let kcal = payload.caloriesKcal.map { String(Int($0.rounded())) } ?? "0"
        let description = payload.description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return "\(kcal):\(description)"
    }
}
