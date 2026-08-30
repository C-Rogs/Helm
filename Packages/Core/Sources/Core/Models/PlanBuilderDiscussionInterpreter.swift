import Foundation

/// Parsed constraints from a free-text "I want a different option" note.
public struct PlanBuilderDiscussionInterpretation: Sendable, Equatable {
    public var daysPerWeek: Int?
    public var sessionDurationMinutes: Int?
    public var preferredTemplateRaw: String?

    public init(
        daysPerWeek: Int? = nil,
        sessionDurationMinutes: Int? = nil,
        preferredTemplateRaw: String? = nil
    ) {
        self.daysPerWeek = daysPerWeek
        self.sessionDurationMinutes = sessionDurationMinutes
        self.preferredTemplateRaw = preferredTemplateRaw
    }

    public var isEmpty: Bool {
        daysPerWeek == nil && sessionDurationMinutes == nil && preferredTemplateRaw == nil
    }
}

public enum PlanBuilderDiscussionInterpreter: Sendable {
    public static func interpret(_ note: String?) -> PlanBuilderDiscussionInterpretation {
        guard let raw = note?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return PlanBuilderDiscussionInterpretation()
        }
        let folded = raw.lowercased()
        return PlanBuilderDiscussionInterpretation(
            daysPerWeek: parseDays(folded),
            sessionDurationMinutes: parseDuration(folded),
            preferredTemplateRaw: parseTemplate(folded)
        )
    }

    public static func applying(_ note: String?, to interview: PlanBuilderInterview) -> PlanBuilderInterview {
        let parsed = interpret(note)
        var next = interview
        if let days = parsed.daysPerWeek {
            next.daysPerWeek = days
        }
        if let minutes = parsed.sessionDurationMinutes {
            next.sessionDurationMinutes = minutes
        }
        return next
    }

    private static func parseDays(_ folded: String) -> Int? {
        let named: [(String, Int)] = [
            ("six day", 6), ("six-day", 6), ("5 day", 5), ("five day", 5), ("five-day", 5),
            ("four day", 4), ("four-day", 4), ("4 day", 4), ("three day", 3), ("three-day", 3),
            ("3 day", 3), ("two day", 2), ("two-day", 2), ("2 day", 2)
        ]
        for (token, days) in named where folded.contains(token) {
            return days
        }
        if let match = folded.range(of: #"\b([2-6])\s*days?\b"#, options: .regularExpression) {
            return Int(folded[match].filter(\.isNumber))
        }
        return nil
    }

    private static func parseDuration(_ folded: String) -> Int? {
        if folded.contains("75") { return 75 }
        if folded.contains("30 minute") || folded.contains("30 min") { return 30 }
        if folded.contains("45") { return 45 }
        if folded.contains("hour") || folded.contains("60 min") { return 60 }
        return nil
    }

    private static func parseTemplate(_ folded: String) -> String? {
        if folded.contains("upper/lower")
            || folded.contains("upper / lower")
            || folded.contains("upper-lower")
            || (folded.contains("upper") && folded.contains("lower"))
        {
            return "upper_lower"
        }
        if folded.contains("full body") || folded.contains("full-body") || folded.contains("fullbody") {
            return "full_body"
        }
        if folded.contains("ppl") || folded.contains("push pull") || folded.contains("push/pull") {
            return "ppl"
        }
        return nil
    }
}
