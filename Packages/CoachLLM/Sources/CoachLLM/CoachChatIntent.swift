import Foundation

/// Lightweight heuristics for chat tool loops (no separate classifier model).
public enum CoachChatIntent: Sendable {
    public static func looksLikeWorkoutReview(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "how was my workout",
            "how did my workout",
            "how did the workout",
            "workout including run",
            "review my workout",
            "my last workout",
            "workout earlier",
            "can't you see it",
            "cant you see it",
            "can you see the",
            "can you see my",
            "in the train history",
            "run i logged",
            "run i did",
            "logged yesterday",
            "workout yesterday",
            "run yesterday",
            "see the run",
            "see my run"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func looksLikeWorkoutStart(_ text: String) -> Bool {
        let lower = text.lowercased()
        let startNeedles = [
            "start the workout",
            "start workout",
            "start today's",
            "start todays",
            "let's go",
            "lets go",
            "begin the workout",
            "lock it in",
            "lock in"
        ]
        if startNeedles.contains(where: { lower.contains($0) }) {
            return true
        }
        // Short confirm after negotiation.
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["yes let's go", "yes lets go", "yes start", "start it"].contains(trimmed)
    }

    public static func looksLikeWorkoutProposal(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "make a",
            "build a",
            "propose",
            "populate my workout",
            "full pull",
            "pull day",
            "push day",
            "leg day"
        ]
        // Proposal language without an immediate start cue.
        return needles.contains(where: { lower.contains($0) }) && !looksLikeWorkoutStart(text)
    }

    public static func looksLikePastMealLookup(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "what did i have",
            "usual breakfast",
            "usual lunch",
            "usual dinner",
            "previous meals",
            "previous breakfast",
            "from other days",
            "copy that breakfast",
            "breakfast on"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func clearsPendingWorkoutStart(_ text: String) -> Bool {
        if looksLikeWorkoutStart(text) { return false }
        if looksLikeWorkoutProposal(text) { return false }
        let lower = text.lowercased()
        let clearNeedles = [
            "hello",
            "hi",
            "hey",
            "clear",
            "how was",
            "how did",
            "review",
            "add ",
            "log ",
            "breakfast",
            "lunch",
            "dinner",
            "calories",
            "protein",
            "sleep",
            "recovery",
            "why did you start",
            "can you see"
        ]
        return clearNeedles.contains { lower.contains($0) }
    }

    public static func looksLikeClearChat(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "clear chat",
            "clear conversation",
            "reset chat",
            "new chat",
            "wipe chat"
        ].contains(trimmed)
    }

    public static func inferredMealQuery(from text: String) -> MealQueryPayload? {
        guard looksLikePastMealLookup(text) else { return nil }
        let lower = text.lowercased()
        let bucket: String?
        if lower.contains("breakfast") {
            bucket = "breakfast"
        } else if lower.contains("lunch") {
            bucket = "lunch"
        } else if lower.contains("dinner") {
            bucket = "dinner"
        } else {
            bucket = nil
        }

        if lower.contains("usual") || lower.contains("previous meals") || lower.contains("from other days") {
            return MealQueryPayload(
                queryType: .usualForBucket,
                bucket: bucket ?? "breakfast",
                lookbackDays: 30
            )
        }
        if let bucket {
            return MealQueryPayload(queryType: .bucketOnDay, bucket: bucket)
        }
        return MealQueryPayload(queryType: .daySummary)
    }

    public static func inferredWorkoutQuery(from text: String, now: Date = Date(), calendar: Calendar = .current) -> WorkoutQueryPayload? {
        guard looksLikeWorkoutReview(text) else { return nil }
        let lower = text.lowercased()
        if lower.contains("yesterday") {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
                return WorkoutQueryPayload(queryType: .latestCompleted)
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return WorkoutQueryPayload(
                queryType: .onDay,
                helmDay: formatter.string(from: yesterday)
            )
        }
        if lower.contains("run") || lower.contains("cardio") {
            return WorkoutQueryPayload(queryType: .includingCardio)
        }
        return WorkoutQueryPayload(queryType: .latestCompleted)
    }

    public static func looksLikeRecoveryLookup(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "hrv trend",
            "hrv this week",
            "hrv last week",
            "how did i sleep",
            "how was my sleep",
            "sleep last night",
            "sleep stages",
            "deep sleep",
            "rem sleep",
            "readiness this week",
            "recovery this week",
            "recovery trend",
            "sleep trend",
            "weight trend",
            "rhr trend"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func inferredRecoveryQuery(from text: String) -> RecoveryQueryPayload? {
        guard looksLikeRecoveryLookup(text) else { return nil }
        let lower = text.lowercased()
        if lower.contains("stage") || lower.contains("deep sleep") || lower.contains("rem sleep")
            || lower.contains("sleep last night") || lower.contains("how did i sleep")
            || lower.contains("how was my sleep") {
            return RecoveryQueryPayload(queryType: .sleepDetail)
        }
        return RecoveryQueryPayload(queryType: .range, lookbackDays: 14)
    }
}
