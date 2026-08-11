import Foundation

/// Timing metadata for each context block so the coach can detect staleness.
public struct CoachContextFreshness: Sendable, Hashable, Codable, Equatable {
    public var generatedAt: Date
    public var blocks: [BlockFreshnessEntry]

    public init(generatedAt: Date = .now, blocks: [BlockFreshnessEntry] = []) {
        self.generatedAt = generatedAt
        self.blocks = blocks
    }

    public mutating func set(_ key: BlockKey, fetchedAt: Date) {
        if let idx = blocks.firstIndex(where: { $0.key == key }) {
            blocks[idx].fetchedAt = fetchedAt
        } else {
            blocks.append(BlockFreshnessEntry(key: key, fetchedAt: fetchedAt))
        }
    }

    /// Returns which blocks are aging or stale, for the staleness suffix.
    public func stalenessSummary(now: Date = .now) -> String {
        let staleBlocks = blocks.compactMap { block -> String? in
            let age = now.timeIntervalSince(block.fetchedAt)
            let ratio = age / Double(block.key.refreshIntervalSeconds)
            guard ratio >= 0.5 else { return nil }
            let status = ratio > 1.0 ? "stale" : "aging"
            let ageStr = Self.formatAge(seconds: Int(age))
            return "\(block.key.rawValue)=\(status)(\(ageStr))"
        }
        guard !staleBlocks.isEmpty else { return "" }
        return "[Context freshness: " + staleBlocks.joined(separator: ", ") + "]"
    }

    private static func formatAge(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h\(seconds % 3600 / 60)m"
    }

    public enum BlockKey: String, Sendable, Hashable, Codable {
        case nutritionDiary
        case todayPrescription
        case recentWorkouts
        case readinessBaselines
        case weekAheadSchedule
        case evidenceIndex
        case trainingPlanSnapshot

        public var refreshIntervalSeconds: Int {
            switch self {
            case .nutritionDiary: return 3600         // 1 hour
            case .todayPrescription: return 3600      // 1 hour or workout-start
            case .recentWorkouts: return 1800          // 30 min
            case .readinessBaselines: return 43200     // 12 hours
            case .weekAheadSchedule: return 86400      // 24 hours
            case .evidenceIndex: return 86400          // 24 hours
            case .trainingPlanSnapshot: return 3600    // 1 hour or workout-complete
            }
        }
    }

    public struct BlockFreshnessEntry: Sendable, Hashable, Codable, Equatable {
        public var key: BlockKey
        public var fetchedAt: Date

        public init(key: BlockKey, fetchedAt: Date) {
            self.key = key
            self.fetchedAt = fetchedAt
        }
    }
}
