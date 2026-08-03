import Foundation

public struct MuscleVolumeBoardRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let weeklySets: Double
    /// Hard sets still on the calendar for this muscle in the forward window.
    public let scheduledSets: Double
    public let mev: Int
    public let mrv: Int
    public let state: HelmState
    /// Calendar days since last hard-set credit; `nil` when never trained.
    public let daysSinceTrained: Int?

    public var projectedSets: Double { weeklySets + scheduledSets }

    public init(
        id: String,
        label: String,
        weeklySets: Double,
        scheduledSets: Double = 0,
        mev: Int,
        mrv: Int,
        state: HelmState,
        daysSinceTrained: Int?
    ) {
        self.id = id
        self.label = label
        self.weeklySets = weeklySets
        self.scheduledSets = scheduledSets
        self.mev = mev
        self.mrv = mrv
        self.state = state
        self.daysSinceTrained = daysSinceTrained
    }
}

public struct MuscleVolumeBoardModel: Sendable, Hashable, Equatable {
    /// Rolling load window for muscle-group set totals (not calendar Mon–Sun).
    public static let loadWindowDays = 7

    public static let loadWindowTitle = "7-day volume"
    public static let loadWindowSubtitle =
        "Logged + scheduled hard sets vs MEV/MRV landmarks, ranked by projected sets"

    public let rows: [MuscleVolumeBoardRow]

    public init(rows: [MuscleVolumeBoardRow]) {
        self.rows = rows.sorted { lhs, rhs in
            if lhs.projectedSets != rhs.projectedSets {
                return lhs.projectedSets > rhs.projectedSets
            }
            return lhs.label < rhs.label
        }
    }

    public var summaryRows: [MuscleVolumeBoardRow] {
        Array(rows.prefix(4))
    }

    public var isEmpty: Bool { rows.isEmpty }
}

public enum MuscleVolumeRecency {
    public static func label(daysSinceTrained: Int?) -> String {
        guard let daysSinceTrained else { return "Never" }
        if daysSinceTrained == 0 { return "Today" }
        if daysSinceTrained == 1 { return "1d ago" }
        return "\(daysSinceTrained)d ago"
    }

    public static func shortLabel(daysSinceTrained: Int?) -> String {
        guard let daysSinceTrained else { return "-" }
        if daysSinceTrained == 0 { return "Today" }
        return "\(daysSinceTrained)d"
    }
}
