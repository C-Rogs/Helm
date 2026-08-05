import Core
import CryptoKit
import Foundation

/// One completed Hevy session after CSV parse + cardio filtering.
public struct HevyCSVParsedSession: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let startedAt: Date
    public let endedAt: Date?
    public let exercises: [ParsedWorkoutExercise]

    public init(
        id: String,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        exercises: [ParsedWorkoutExercise]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
    }

    public var parsedWorkout: ParsedWorkout {
        ParsedWorkout(title: title, exercises: exercises)
    }

    public var setCount: Int {
        exercises.reduce(0) { $0 + $1.sets.count }
    }
}

public struct HevyCSVParseResult: Sendable, Hashable {
    public let sessions: [HevyCSVParsedSession]
    public let clippedAwaySessionCount: Int
    public let skippedCardioSetCount: Int
    public let uniqueExerciseTitles: [String]

    public init(
        sessions: [HevyCSVParsedSession],
        clippedAwaySessionCount: Int,
        skippedCardioSetCount: Int,
        uniqueExerciseTitles: [String]
    ) {
        self.sessions = sessions
        self.clippedAwaySessionCount = clippedAwaySessionCount
        self.skippedCardioSetCount = skippedCardioSetCount
        self.uniqueExerciseTitles = uniqueExerciseTitles
    }

    public var totalSetCount: Int {
        sessions.reduce(0) { $0 + $1.setCount }
    }

    public var dateRange: ClosedRange<Date>? {
        guard
            let first = sessions.map(\.startedAt).min(),
            let last = sessions.map(\.startedAt).max()
        else {
            return nil
        }
        return first ... last
    }
}

public enum HevyCSVParserError: Error, Sendable, Equatable {
    case emptyDocument
    case missingRequiredHeader(String)
    case unreadableDate(String)
}

extension HevyCSVParserError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "Hevy CSV is empty."
        case let .missingRequiredHeader(name):
            "Hevy CSV is missing column: \(name)"
        case let .unreadableDate(value):
            "Could not parse Hevy date: \(value)"
        }
    }
}

/// Parses Hevy workout export CSV into completed sessions (90-day clip by default).
public enum HevyCSVParser {
    public static let defaultLookbackDays = 90

    public static func parse(
        csvText: String,
        lookbackDays: Int = defaultLookbackDays,
        referenceNow: Date? = nil
    ) throws -> HevyCSVParseResult {
        let trimmed = normalizePastedText(csvText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HevyCSVParserError.emptyDocument }

        let rows = try CSVTable.parse(trimmed)
        guard let headerRow = rows.first else { throw HevyCSVParserError.emptyDocument }
        let headers = headerRow.enumerated().reduce(into: [String: Int]()) { result, entry in
            let name = entry.element
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !name.isEmpty, result[name] == nil else { return }
            result[name] = entry.offset
        }

        func require(_ name: String) throws -> Int {
            guard let index = headers[name] else {
                throw HevyCSVParserError.missingRequiredHeader(name)
            }
            return index
        }

        let titleIdx = try require("title")
        let startIdx = try require("start_time")
        let endIdx = try require("end_time")
        let exerciseIdx = try require("exercise_title")
        let setIndexIdx = try require("set_index")
        let setTypeIdx = try require("set_type")
        let repsIdx = try require("reps")
        let rpeIdx = headers["rpe"]
        let weightKgIdx = headers["weight_kg"]
        let weightLbsIdx = headers["weight_lbs"]
        guard weightKgIdx != nil || weightLbsIdx != nil else {
            throw HevyCSVParserError.missingRequiredHeader("weight_kg")
        }

        struct RawSet {
            let exerciseTitle: String
            let setIndex: Int
            let setType: SetType
            let mass: Mass?
            let reps: Int
            let rpe: Double?
        }

        struct RawSession {
            let title: String
            let startedAt: Date
            let endedAt: Date?
            var sets: [RawSet]
        }

        var sessionsByKey: [String: RawSession] = [:]
        var sessionOrder: [String] = []
        var skippedCardio = 0

        for row in rows.dropFirst() {
            guard row.count > max(titleIdx, startIdx, endIdx, exerciseIdx, setIndexIdx, setTypeIdx, repsIdx) else {
                continue
            }

            let repsText = row[repsIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let reps = Int(repsText), reps > 0 else {
                skippedCardio += 1
                continue
            }

            let startText = row[startIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let startedAt = try parseHevyDate(startText)
            let endText = row[endIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let endedAt = endText.isEmpty ? nil : try parseHevyDate(endText)
            let title = row[titleIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            let exerciseTitle = row[exerciseIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !exerciseTitle.isEmpty else { continue }

            let setIndex = Int(row[setIndexIdx].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let setType = mapSetType(row[setTypeIdx])
            let mass = parseMass(row: row, kgIndex: weightKgIdx, lbsIndex: weightLbsIdx)
            let rpe: Double? = {
                guard let rpeIdx else { return nil }
                let text = row[rpeIdx].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return Double(text)
            }()

            let key = "\(startText)|\(title)"
            if sessionsByKey[key] == nil {
                sessionsByKey[key] = RawSession(
                    title: title,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    sets: []
                )
                sessionOrder.append(key)
            }
            sessionsByKey[key]?.sets.append(
                RawSet(
                    exerciseTitle: exerciseTitle,
                    setIndex: setIndex,
                    setType: setType,
                    mass: mass,
                    reps: reps,
                    rpe: rpe
                )
            )
        }

        let allSessions: [RawSession] = sessionOrder.compactMap { sessionsByKey[$0] }
        let newest = allSessions.map(\.startedAt).max() ?? referenceNow ?? Date()
        let cutoff = newest.addingTimeInterval(-Double(lookbackDays) * 86_400)

        var kept: [HevyCSVParsedSession] = []
        var clippedAway = 0

        for raw in allSessions {
            guard raw.startedAt >= cutoff else {
                clippedAway += 1
                continue
            }

            var exerciseOrder: [String] = []
            var setsByExercise: [String: [RawSet]] = [:]
            for set in raw.sets {
                if setsByExercise[set.exerciseTitle] == nil {
                    exerciseOrder.append(set.exerciseTitle)
                    setsByExercise[set.exerciseTitle] = []
                }
                setsByExercise[set.exerciseTitle]?.append(set)
            }

            let exercises: [ParsedWorkoutExercise] = exerciseOrder.compactMap { title in
                guard let sets = setsByExercise[title], !sets.isEmpty else { return nil }
                let sorted = sets.sorted { $0.setIndex < $1.setIndex }
                return ParsedWorkoutExercise(
                    exerciseTitle: title,
                    sets: sorted.enumerated().map { offset, set in
                        ParsedWorkoutSet(
                            setIndex: offset + 1,
                            setType: set.setType,
                            mass: set.mass,
                            reps: set.reps,
                            rpe: set.rpe
                        )
                    }
                )
            }

            guard !exercises.isEmpty else { continue }

            kept.append(
                HevyCSVParsedSession(
                    id: deterministicSessionID(title: raw.title, startedAt: raw.startedAt),
                    title: raw.title,
                    startedAt: raw.startedAt,
                    endedAt: raw.endedAt,
                    exercises: exercises
                )
            )
        }

        let titles = Array(Set(kept.flatMap { $0.exercises.map(\.exerciseTitle) })).sorted()
        return HevyCSVParseResult(
            sessions: kept,
            clippedAwaySessionCount: clippedAway,
            skippedCardioSetCount: skippedCardio,
            uniqueExerciseTitles: titles
        )
    }

    public static func deterministicSessionID(title: String, startedAt: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: startedAt)
        let digest = SHA256.hash(data: Data("\(title)|\(stamp)".utf8))
        let hex = digest.prefix(10).map { String(format: "%02x", $0) }.joined()
        return "hevy-\(hex)"
    }

    /// Notes and mail clients substitute curly quotes and non-breaking spaces when text is pasted.
    static func normalizePastedText(_ text: String) -> String {
        var normalized = text
        for (from, to) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{00A0}", " ")] {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }
        return normalized
    }

    private static func mapSetType(_ raw: String) -> SetType {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "warmup", "warm-up", "warm_up":
            return .warmup
        case "dropset", "drop_set", "drop-set":
            return .dropSet
        case "failure":
            return .failure
        default:
            return .normal
        }
    }

    private static func parseMass(row: [String], kgIndex: Int?, lbsIndex: Int?) -> Mass? {
        if let kgIndex, kgIndex < row.count {
            let text = row[kgIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if let kg = Double(text), kg >= 0 {
                return Mass(kilograms: kg)
            }
        }
        if let lbsIndex, lbsIndex < row.count {
            let text = row[lbsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if let lbs = Double(text), lbs >= 0 {
                return Mass(pounds: lbs)
            }
        }
        return nil
    }

    private static func parseHevyDate(_ text: String) throws -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        if let date = formatter.date(from: trimmed) {
            return date
        }
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        if let date = formatter.date(from: trimmed) {
            return date
        }
        throw HevyCSVParserError.unreadableDate(trimmed)
    }
}

/// Minimal RFC4180-ish CSV table parser (quoted fields, commas, newlines).
enum CSVTable {
    static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        func pushField() {
            row.append(field)
            field = ""
        }

        func pushRow() {
            pushField()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
            row = []
        }

        while index < text.endIndex {
            let char = text[index]
            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    pushField()
                case "\n":
                    pushRow()
                case "\r":
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                    pushRow()
                default:
                    field.append(char)
                }
            }
            index = text.index(after: index)
        }

        if inQuotes || !field.isEmpty || !row.isEmpty {
            pushRow()
        }
        return rows
    }
}
