import Foundation

public struct MuscleVolumeBoardRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let weeklySets: Double
    public let mev: Int
    public let mrv: Int
    public let state: HelmState
    /// Calendar days since last hard-set credit; `nil` when never trained.
    public let daysSinceTrained: Int?

    public init(
        id: String,
        label: String,
        weeklySets: Double,
        mev: Int,
        mrv: Int,
        state: HelmState,
        daysSinceTrained: Int?
    ) {
        self.id = id
        self.label = label
        self.weeklySets = weeklySets
        self.mev = mev
        self.mrv = mrv
        self.state = state
        self.daysSinceTrained = daysSinceTrained
    }
}

public struct MuscleVolumeBoardModel: Sendable, Hashable, Equatable {
    public let rows: [MuscleVolumeBoardRow]

    public init(rows: [MuscleVolumeBoardRow]) {
        self.rows = rows
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
