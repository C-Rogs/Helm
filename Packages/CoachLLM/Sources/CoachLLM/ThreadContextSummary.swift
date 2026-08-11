import Foundation

/// A structured summary of the oldest portion of a coaching conversation,
/// injected back into context so the coach remembers decisions, questions,
/// and commitments without exceeding the context window.
public struct ThreadContextSummary: Sendable, Hashable, Codable, Equatable {
    public var decisions: String
    public var openQuestions: String
    public var coachCommitments: String
    public var athleteState: String
    public var activeNegotiations: String
    public var nutritionContext: String
    public var generatedAt: Date
    public var compressedMessageCount: Int

    public init(
        decisions: String = "",
        openQuestions: String = "",
        coachCommitments: String = "",
        athleteState: String = "",
        activeNegotiations: String = "",
        nutritionContext: String = "",
        generatedAt: Date = .now,
        compressedMessageCount: Int = 0
    ) {
        self.decisions = decisions
        self.openQuestions = openQuestions
        self.coachCommitments = coachCommitments
        self.athleteState = athleteState
        self.activeNegotiations = activeNegotiations
        self.nutritionContext = nutritionContext
        self.generatedAt = generatedAt
        self.compressedMessageCount = compressedMessageCount
    }

    public var isEmpty: Bool {
        decisions.isEmpty && openQuestions.isEmpty && coachCommitments.isEmpty
            && athleteState.isEmpty && activeNegotiations.isEmpty && nutritionContext.isEmpty
    }

    /// Compressed text block for LLM consumption (~150-200 tokens).
    public var promptBlock: String {
        var lines: [String] = []
        let sections: [(String, String)] = [
            ("# Decisions Made", decisions.nilIfEmpty ?? "None."),
            ("# Open Questions", openQuestions.nilIfEmpty ?? "None."),
            ("# Coach Commitments", coachCommitments.nilIfEmpty ?? "None."),
            ("# Athlete State", athleteState.nilIfEmpty ?? "None."),
            ("# Active Negotiations", activeNegotiations.nilIfEmpty ?? "None."),
            ("# Nutrition Context", nutritionContext.nilIfEmpty ?? "None.")
        ]
        for (header, value) in sections {
            lines.append("\(header)\n\(value)")
        }
        return "[THREAD CONTEXT]\n" + lines.joined(separator: "\n\n")
    }

    /// Extraction prompt for summarisation (~7 structured reminders hidden in system instruction).
    public static let summarisationPrompt = """
    Summarise this coaching conversation into exactly the sections below.
    Use the same language and tone as the conversation.
    Cross-reference the Memory Profile for athlete details when useful.

    # Decisions Made
    Key decisions agreed to: exercise swaps, weight targets, volume changes, timing/scheduling, deload acceptance, phase changes.

    # Open Questions
    Unanswered athlete questions that the coach should follow up on next.

    # Coach Commitments
    Any "I'll check…" or "I'll look into…" promises the coach made.

    # Athlete State
    Physical/emotional state, readiness trends, pain mentions, fatigue cues.

    # Active Negotiations
    Mid-negotiation workout plan state (exercises in play, what hasn't been locked).

    # Nutrition Context
    Today's food log, dietary constraints mentioned, meals discussed.

    Rules:
    - Be specific: exact numbers, dates, exercise names.
    - Preserve chronological order within each section.
    - Discard greetings, thanks, repetition, "let me check".
    - NEVER discard open questions or coach commitments.
    - Write "None." if a section is empty.
    - Aim for 150-200 tokens total.
    """
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
