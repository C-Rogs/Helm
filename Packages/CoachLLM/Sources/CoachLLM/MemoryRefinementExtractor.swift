import Foundation

/// Invoked after a coaching session ends to extract new observations
/// into MemoryProfile refinements.
public enum MemoryRefinementExtractor: Sendable {

    /// System prompt sent to Gemini for extraction (cheap Flash model).
    public static let extractionPrompt = """
    You are analysing a coaching conversation between a training AI coach
    and an athlete. Extract any NEW observations about the athlete that
    should be remembered for future sessions.

    Output ONLY valid JSON matching this schema:
    {
      "schemaVersion": "memory_refinement.v1",
      "reply": "short coach-facing summary of what was learned",
      "refinements": [
        {
          "field": "preferences|whatHasWorked|trainingResponses|nutritionPatterns|injuryHistory",
          "action": "add|merge|replace",
          "proposedValue": "suggested or merged text",
          "confidence": "low|medium|high",
          "evidence": [
            {
              "sessionDate": "YYYY-MM-DD",
              "excerpt": "brief verbatim quote from conversation"
            }
          ],
          "rationale": "why this update is warranted"
        }
      ]
    }

    Rules:
    - Only extract genuinely new observations not already obvious from context.
    - Skip if the athlete just logged meals or exchanged greetings.
    - Prefer explicit athlete statements over inferred patterns.
    - Confidence = high for explicit statements, medium for clear patterns,
      low for tentative hints.
    - Provide at most 3 refinements per session.
    - If nothing new was learned, return an empty refinements array.
    """

    /// Current MemoryProfile values the extractor should compare against.
    public static func profileContext(from profile: MemoryProfile) -> String {
        var parts: [String] = []
        if !profile.preferences.isEmpty {
            parts.append("Current preferences: \(profile.preferences)")
        }
        if !profile.whatHasWorked.isEmpty {
            parts.append("What has worked: \(profile.whatHasWorked)")
        }
        if !profile.trainingResponses.isEmpty {
            parts.append("Training responses: \(profile.trainingResponses)")
        }
        if !profile.nutritionPatterns.isEmpty {
            parts.append("Nutrition patterns: \(profile.nutritionPatterns)")
        }
        if !profile.injuryHistory.isEmpty {
            parts.append("Injury history: \(profile.injuryHistory)")
        }
        guard !parts.isEmpty else { return "" }
        return "Existing memory:\n" + parts.joined(separator: "\n")
    }

    /// Parse the raw response string into a payload.
    /// Accepts JSON blocks embedded in text (uses the same block-finding logic as the main chat).
    public static func parse(_ raw: String) -> MemoryRefinementPayload? {
        let blocks = CoachEmbeddedJSONBlockFinder.blocks(in: raw)
        let jsonBody: String
        if let block = blocks.first, !block.isEmpty {
            jsonBody = block
        } else {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") else { return nil }
            jsonBody = trimmed
        }
        guard let data = jsonBody.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MemoryRefinementPayload.self, from: data)
    }
}
