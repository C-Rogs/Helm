import Foundation

public enum WeekAheadSessionStatus: String, Sendable, Hashable, Equatable {
    case upcoming
    case today
    case completed
    case missed
}

public struct WeekAheadScheduleRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let dayLabel: String
    public let splitLabel: String
    public let note: String?
    public let status: WeekAheadSessionStatus
    public let isToday: Bool

    public init(
        id: String,
        dayLabel: String,
        splitLabel: String,
        note: String? = nil,
        status: WeekAheadSessionStatus,
        isToday: Bool
    ) {
        self.id = id
        self.dayLabel = dayLabel
        self.splitLabel = splitLabel
        self.note = note
        self.status = status
        self.isToday = isToday
    }

    public var statusLabel: String? {
        switch status {
        case .completed:
            "Done"
        case .missed:
            "Missed"
        case .today, .upcoming:
            nil
        }
    }
}

public struct WeekAheadScheduleModel: Sendable, Hashable, Equatable {
    public let rows: [WeekAheadScheduleRow]

    public init(rows: [WeekAheadScheduleRow]) {
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

public enum WeekAheadScheduleSnapshot {
    public static func text(for model: WeekAheadScheduleModel) -> String {
        var lines = ["# Week ahead"]
        if model.rows.isEmpty {
            lines.append("- none")
        } else {
            for row in model.rows {
                let note = row.note.map { " | note=\($0)" } ?? ""
                lines.append(
                    "- \(row.dayLabel): \(row.splitLabel) | status=\(row.status.rawValue) | today=\(row.isToday)\(note)"
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}
