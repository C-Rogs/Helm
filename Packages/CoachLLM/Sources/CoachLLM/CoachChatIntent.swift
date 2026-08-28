import Core
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

    /// True when the user asks coach to build/draft a new training plan,
    /// which should open the plan-builder flow instead of a chat answer.
    public static func looksLikePlanBuilderRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let planNeedles = [
            "build me a plan",
            "build a plan",
            "build a new plan",
            "make me a plan",
            "make a new plan",
            "draft a plan",
            "draft a new plan",
            "design a plan",
            "design a new plan",
            "new training plan",
            "rebuild my plan",
            "new program",
            "start a new block",
            "plan builder"
        ]
        guard planNeedles.contains(where: { lower.contains($0) }) else { return false }
        // Single-workout proposals are handled by the workout flow, not the builder.
        return !looksLikeWorkoutProposal(text) && !looksLikeWorkoutStart(text)
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

    public static func looksLikeCalendarLookup(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "what's on my calendar",
            "whats on my calendar",
            "what is on my calendar",
            "what events",
            "what do i have on",
            "what do i have today",
            "what's on today",
            "whats on today",
            "why am i busy",
            "why am i marked busy",
            "why does it think i'm busy",
            "why does it think im busy",
            "calendar today",
            "calendar tomorrow",
            "my calendar",
            "meetings today",
            "meetings tomorrow"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func inferredCalendarQuery(
        from text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CalendarQueryPayload? {
        guard looksLikeCalendarLookup(text) else { return nil }
        let lower = text.lowercased()
        if lower.contains("tomorrow") {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return CalendarQueryPayload(queryType: .today)
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return CalendarQueryPayload(
                queryType: .day,
                helmDay: formatter.string(from: tomorrow)
            )
        }
        if lower.contains("week") || lower.contains("ahead") {
            return CalendarQueryPayload(queryType: .weekAhead)
        }
        return CalendarQueryPayload(queryType: .today)
    }

    public static func looksLikeTrendsLookup(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "trimp history",
            "trimp over time",
            "training load history",
            "how has my weight trended",
            "weight trend",
            "my e1rm",
            "e1rm progression",
            "strength progression",
            "energy balance history",
            "calorie balance history",
            "readiness history",
            "readiness over time",
            "how has readiness trended",
            "trend data",
            "my trends"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func inferredTrendsQuery(from text: String) -> TrendsQueryPayload? {
        guard looksLikeTrendsLookup(text) else { return nil }
        let lower = text.lowercased()
        if lower.contains("trimp") || lower.contains("training load") || lower.contains("strain") {
            return TrendsQueryPayload(queryType: .trimp)
        }
        if lower.contains("weight") || lower.contains("trend") && lower.contains("weight") {
            return TrendsQueryPayload(queryType: .weight)
        }
        if lower.contains("e1rm") || lower.contains("strength") || lower.contains("progression") {
            return TrendsQueryPayload(queryType: .e1rm)
        }
        if lower.contains("energy") && lower.contains("balance") || lower.contains("calorie") {
            return TrendsQueryPayload(queryType: .energyBalance)
        }
        if lower.contains("readiness") {
            return TrendsQueryPayload(queryType: .readiness)
        }
        return TrendsQueryPayload(queryType: .all)
    }

    // MARK: - Nutrition Query Inference

    public static func looksLikeNutritionLookup(_ text: String) -> Bool {
        let lower = text.lowercased()
        let needles = [
            "how many calories should i eat",
            "what should my macros be",
            "what are my targets",
            "what's my tdee",
            "what is my tdee",
            "trend weight",
            "nutrition history",
            "calorie history",
            "past intake",
            "how much should i eat",
            "macro target",
            "calorie target",
            "weekly budget",
            "week budget",
            "my nutrition budget",
            "nutrition plan",
            "what can i eat today",
            "how many calories today"
        ]
        return needles.contains(where: lower.contains)
    }

    public static func inferredNutritionQuery(from text: String) -> NutritionQueryPayload? {
        guard looksLikeNutritionLookup(text) else { return nil }
        let lower = text.lowercased()
        // History before weekly so "weekly calorie history" → range, not budget.
        if lower.contains("history") || lower.contains("past intake") || lower.contains("lookback") {
            return NutritionQueryPayload(queryType: .range)
        }
        if lower.contains("budget") || lower.contains("week ahead")
            || lower.contains("weekly budget") || lower.contains("week budget")
        {
            return NutritionQueryPayload(queryType: .weeklyBudget)
        }
        return NutritionQueryPayload(queryType: .today)
    }

    /// Exercise/set/load change to the current session, not a new plan or a past-workout review.
    public static func looksLikeSessionAdjustment(_ text: String) -> Bool {
        if looksLikeWorkoutStart(text) { return false }
        if looksLikeWorkoutReview(text) { return false }
        if looksLikeNutritionLookup(text) { return false }
        if looksLikePastMealLookup(text) { return false }
        if looksLikePlanBuilderRequest(text) { return false }

        let lower = text.lowercased()
        if looksLikePlanLevelChange(lower) { return false }

        let needles = [
            "swap ",
            " swap",
            "replace ",
            "instead of",
            "drop a set",
            "drop one set",
            "add a set",
            "add one set",
            "extra set",
            "one more set",
            "another set",
            "fewer sets",
            "less sets",
            "take a set off",
            "remove a set",
            "skip ",
            "do first",
            "reorder",
            "lighter on",
            "heavier on",
            "kg off",
            "kilos off",
            "warmup set",
            "warm-up set",
            "drop the weight",
            "bump the weight",
            "take weight off"
        ]
        return needles.contains { lower.contains($0) }
    }

    /// Pre-start Chat should only hijack when the athlete named today's session.
    public static func looksLikeTodaySessionChange(_ text: String) -> Bool {
        let lower = text.lowercased()
        let cues = [
            "today's workout",
            "todays workout",
            "today's session",
            "todays session",
            "this session",
            "this workout",
            "before i start",
            "today's prescribed",
            "todays prescribed"
        ]
        return cues.contains { lower.contains($0) }
    }

    public static func shouldRouteChatToSessionCoach(_ text: String, sessionIsLive: Bool) -> Bool {
        guard looksLikeSessionAdjustment(text) else { return false }
        if sessionIsLive { return true }
        return looksLikeTodaySessionChange(text)
    }

    /// Day named in the athlete's message. Nil means they did not name a day.
    public static func namedHelmDay(
        in text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HelmDay? {
        let lower = text.lowercased()
        if lower.contains("yesterday") {
            guard let date = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return HelmDay.day(for: date, calendar: calendar)
        }
        let todayCues = [" today", "today ", "today,", "this morning", "this afternoon", "tonight"]
        if todayCues.contains(where: { lower.contains($0) }) || lower == "today" || lower.hasPrefix("today ") {
            return HelmDay.day(for: now, calendar: calendar)
        }
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        for (name, weekday) in weekdays where lower.contains(name) {
            let todayWeekday = calendar.component(.weekday, from: now)
            var delta = weekday - todayWeekday
            if delta > 0 { delta -= 7 }
            guard let date = calendar.date(byAdding: .day, value: delta, to: now) else { return nil }
            return HelmDay.day(for: date, calendar: calendar)
        }
        return nil
    }

    /// Chat food logs ignore a hidden Nutrition diary day unless the athlete named a date.
    public static func resolvedChatFoodHelmDay(
        userText: String,
        payloadDay: String?,
        nutritionTabVisible: Bool,
        viewedNutritionDay: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> HelmDay {
        if let named = namedHelmDay(in: userText, now: now, calendar: calendar) {
            return named
        }
        if nutritionTabVisible {
            if let payloadDay, let parsed = parseHelmDay(payloadDay) {
                return parsed
            }
            if let viewedNutritionDay, let parsed = parseHelmDay(viewedNutritionDay) {
                return parsed
            }
        }
        return HelmDay.day(for: now, calendar: calendar)
    }

    public static func inferredNavigateTab(from text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("open train")
            || lower.contains("go to train")
            || lower.contains("switch to train")
            || lower.contains("take me to train") {
            return "train"
        }
        if lower.contains("open nutrition")
            || lower.contains("go to nutrition")
            || lower.contains("open diary")
            || lower.contains("open the diary")
            || (lower.contains("food log") && lower.hasPrefix("open")) {
            return "nutrition"
        }
        if lower.hasPrefix("open"),
           lower.contains("snack")
            || lower.contains("meal i just")
            || lower.contains("entry i just")
            || lower.contains("entry of") {
            return "nutrition"
        }
        if lower.contains("open dashboard") || lower.contains("go to dashboard") {
            return "dashboard"
        }
        if lower.contains("open settings") || lower.contains("go to settings") {
            return "settings"
        }
        if lower.contains("open chat") { return "chat" }
        return nil
    }

    private static func parseHelmDay(_ raw: String) -> HelmDay? {
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

    private static func looksLikePlanLevelChange(_ lower: String) -> Bool {
        let planNeedles = [
            "training plan",
            "new plan",
            "mesocycle",
            "days a week",
            "days per week",
            "my program",
            "my programme",
            "the program",
            "the programme"
        ]
        return planNeedles.contains { lower.contains($0) }
    }
}
