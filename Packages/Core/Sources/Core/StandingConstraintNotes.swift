import Foundation

/// Parseable standing-constraint lines for temporary joint recovery windows.
///
/// Format: `YYYY-MM-DD [until:YYYY-MM-DD] [joint:shoulder] Note text`
/// Optional `[resolved:YYYY-MM-DD]` marks a line cleared early.
public enum StandingConstraintNotes: Sendable {
    public static let defaultWindowDays = 3
    public static let easeBackDays = 3

    public struct Evaluation: Sendable, Equatable {
        /// Joints still inside an active recovery window (e.g. `shoulder`).
        public let activeJoints: Set<String>
        /// Brief lines for session design / pre-start coach.
        public let rationaleNotes: [String]
        public let encourageWarmUpStretch: Bool

        public var pauseVerticalPress: Bool {
            activeJoints.contains("shoulder")
        }

        public static let empty = Evaluation(
            activeJoints: [],
            rationaleNotes: [],
            encourageWarmUpStretch: false
        )
    }

    public static func formatAddLine(
        note: String,
        joint: String?,
        notedOn: HelmDay,
        until: HelmDay
    ) -> String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedJoint = normalizedJoint(joint) ?? inferJoint(from: trimmedNote) ?? "general"
        return "\(notedOn.formatted) [until:\(until.formatted)] [joint:\(resolvedJoint)] \(trimmedNote)"
    }

    public static func defaultUntil(from notedOn: HelmDay) -> HelmDay {
        notedOn.adding(days: defaultWindowDays)
    }

    public static func append(
        note: String,
        joint: String?,
        notedOn: HelmDay,
        until: HelmDay?,
        to existing: String
    ) -> String {
        let line = formatAddLine(
            note: note,
            joint: joint,
            notedOn: notedOn,
            until: until ?? defaultUntil(from: notedOn)
        )
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return line }
        return trimmed + "\n" + line
    }

    /// Marks matching open lines as resolved (keeps history).
    public static func clear(
        joint: String?,
        on day: HelmDay,
        in existing: String
    ) -> String {
        let targetJoint = normalizedJoint(joint)
        let lines = existing
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let updated = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return line }
            guard parse(trimmed) != nil else { return line }
            if trimmed.contains("[resolved:") { return line }
            if let targetJoint {
                let lineJoint = jointTag(in: trimmed) ?? inferJoint(from: trimmed)
                guard lineJoint == targetJoint else { return line }
            }
            return trimmed + " [resolved:\(day.formatted)]"
        }
        return updated.joined(separator: "\n")
    }

    public static func evaluate(_ text: String, on day: HelmDay) -> Evaluation {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var activeJoints = Set<String>()
        var notes: [String] = []
        var encourage = false

        for line in lines {
            guard let parsed = parse(line), parsed.resolvedOn == nil else { continue }
            let joint = parsed.joint
            if day <= parsed.until {
                activeJoints.insert(joint)
                encourage = true
                if joint == "shoulder" {
                    notes.append(
                        "Shoulder recovery window through \(parsed.until.formatted): soft pause overhead pressing; warm up and stretch."
                    )
                } else {
                    notes.append(
                        "\(joint.capitalized) recovery window through \(parsed.until.formatted): warm up and stretch; ease related loading."
                    )
                }
            } else if day <= parsed.until.adding(days: easeBackDays) {
                encourage = true
                if joint == "shoulder" {
                    notes.append(
                        "Shoulder recently noted - warm up thoroughly; overhead pressing is allowed again."
                    )
                } else {
                    notes.append(
                        "\(joint.capitalized) recently noted - warm up thoroughly as you ease back."
                    )
                }
            }
        }

        // Deduplicate near-identical notes while preserving order.
        var seen = Set<String>()
        let uniqueNotes = notes.filter { seen.insert($0).inserted }

        return Evaluation(
            activeJoints: activeJoints,
            rationaleNotes: Array(uniqueNotes.prefix(2)),
            encourageWarmUpStretch: encourage
        )
    }

    // MARK: - Parsing

    struct ParsedLine: Sendable, Equatable {
        let notedOn: HelmDay
        let until: HelmDay
        let joint: String
        let resolvedOn: HelmDay?
        let body: String
    }

    static func parse(_ line: String) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let notedOn = leadingDay(in: trimmed) else { return nil }

        if trimmed.contains("[resolved:") {
            // Still parse for clear idempotency; evaluate skips resolved.
        }

        let until: HelmDay
        if let untilTag = tagValue("until", in: trimmed), let parsedUntil = HelmDay(formatted: untilTag) {
            until = parsedUntil
        } else {
            until = notedOn.adding(days: defaultWindowDays)
        }

        let joint = jointTag(in: trimmed)
            ?? inferJoint(from: trimmed)
            ?? "general"

        let resolvedOn: HelmDay?
        if let resolvedTag = tagValue("resolved", in: trimmed) {
            resolvedOn = HelmDay(formatted: resolvedTag)
        } else {
            resolvedOn = nil
        }

        let body = stripTags(from: trimmed)
        return ParsedLine(
            notedOn: notedOn,
            until: until,
            joint: joint,
            resolvedOn: resolvedOn,
            body: body
        )
    }

    private static func leadingDay(in line: String) -> HelmDay? {
        let prefix = String(line.prefix(10))
        return HelmDay(formatted: prefix)
    }

    private static func jointTag(in line: String) -> String? {
        normalizedJoint(tagValue("joint", in: line))
    }

    private static func tagValue(_ name: String, in line: String) -> String? {
        let pattern = "\\[\(name):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(from line: String) -> String {
        var result = line
        if result.count >= 10 {
            let datePrefix = String(result.prefix(10))
            if HelmDay(formatted: datePrefix) != nil {
                result = String(result.dropFirst(10))
                if result.hasPrefix(":") {
                    result = String(result.dropFirst())
                }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"\[[^\]]+\]"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedJoint(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        switch value {
        case "shoulders": return "shoulder"
        case "knees": return "knee"
        default: return value
        }
    }

    private static func inferJoint(from text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("shoulder")
            || lower.contains("overhead")
            || lower.contains("ohp")
            || lower.contains("rotator")
        {
            return "shoulder"
        }
        if lower.contains("knee") { return "knee" }
        if lower.contains("elbow") { return "elbow" }
        if lower.contains("wrist") { return "wrist" }
        if lower.contains("hip") { return "hip" }
        if lower.contains("back") || lower.contains("lumbar") { return "back" }
        return nil
    }
}

public extension HelmDay {
    init?(formatted: String) {
        let parts = formatted.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              month >= 1, month <= 12,
              day >= 1, day <= 31
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }
}
