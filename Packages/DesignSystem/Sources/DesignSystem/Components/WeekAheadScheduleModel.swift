import Foundation

public enum WeekAheadSessionStatus: String, Sendable, Hashable, Equatable {
    case upcoming
    case today
    case completed
    case missed
    case shifted
    case skipped
    case rest
}

public struct WeekAheadScheduleRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let dayLabel: String
    public let splitLabel: String
    public let note: String?
    public let status: WeekAheadSessionStatus
    public let driftNote: String?
    public let busyDayHint: String?
    public let isToday: Bool
    public let isPartiallyBlocked: Bool

    public init(
        id: String,
        dayLabel: String,
        splitLabel: String,
        note: String? = nil,
        status: WeekAheadSessionStatus,
        driftNote: String? = nil,
        busyDayHint: String? = nil,
        isToday: Bool,
        isPartiallyBlocked: Bool = false
    ) {
        self.id = id
        self.dayLabel = dayLabel
        self.splitLabel = splitLabel
        self.note = note
        self.status = status
        self.driftNote = driftNote
        self.busyDayHint = busyDayHint
        self.isToday = isToday
        self.isPartiallyBlocked = isPartiallyBlocked
    }

    public var statusLabel: String? {
        switch status {
        case .completed:
            "Done"
        case .missed:
            "Missed"
        case .shifted:
            "Moved"
        case .skipped:
            "Skipped"
        case .rest:
            "Rest"
        case .today, .upcoming:
            nil
        }
    }

    public var isRestDay: Bool {
        status == .rest
    }
}

public struct WeekAheadScheduleModel: Sendable, Hashable, Equatable {
    public let rows: [WeekAheadScheduleRow]

    public init(rows: [WeekAheadScheduleRow]) {
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }

    public var chronologicalRows: [WeekAheadScheduleRow] {
        rows.sorted { $0.id < $1.id }
    }

    public var collapsedSummary: String {
        guard !rows.isEmpty else { return "No days planned" }

        let ordered = chronologicalRows
        let trainingCount = ordered.filter { !$0.isRestDay }.count
        let restCount = ordered.count - trainingCount
        if let next = ordered.first(where: {
            $0.status == .today || $0.status == .upcoming || ($0.isToday && $0.isRestDay)
        }) {
            let busySuffix = next.busyDayHint.map { " · \($0)" } ?? ""
            return "\(trainingCount) sessions · \(restCount) rest · \(next.splitLabel) next\(busySuffix)"
        }

        return "\(trainingCount) sessions · \(restCount) rest"
    }
}

public enum WeekAheadScheduleSnapshot {
    public static func text(for model: WeekAheadScheduleModel) -> String {
        var lines = ["# Week ahead"]
        if model.rows.isEmpty {
            lines.append("- none")
        } else {
            for row in model.rows {
                let note = row.note.map { " | note=\($0)" } ?? ""
                let drift = row.driftNote.map { " | drift=\($0)" } ?? ""
                let busy = row.busyDayHint.map { " | busy=\($0)" } ?? ""
                lines.append(
                    "- \(row.dayLabel): \(row.splitLabel) | status=\(row.status.rawValue) | today=\(row.isToday)\(note)\(drift)\(busy)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}
