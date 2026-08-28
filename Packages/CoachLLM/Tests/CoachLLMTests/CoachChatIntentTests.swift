import CoachLLM
import Testing

@Suite("CoachChatIntent")
struct CoachChatIntentTests {
    @Test("detects workout start vs proposal")
    func startVersusProposal() {
        #expect(CoachChatIntent.looksLikeWorkoutProposal("Make a full pull day workout"))
        #expect(!CoachChatIntent.looksLikeWorkoutStart("Make a full pull day workout"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Start the workout"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Yes let's go"))
        #expect(CoachChatIntent.clearsPendingWorkoutStart("How was my workout earlier"))
        #expect(!CoachChatIntent.clearsPendingWorkoutStart("Start the workout"))
    }

    @Test("infers workout and meal queries")
    func infersQueries() {
        #expect(CoachChatIntent.inferredWorkoutQuery(from: "How was my workout earlier")?.queryType == .latestCompleted)
        #expect(CoachChatIntent.inferredWorkoutQuery(from: "How was my workout including run")?.queryType == .includingCardio)
        #expect(CoachChatIntent.inferredMealQuery(from: "What did I have for breakfast on tuesday")?.queryType == .bucketOnDay)
        #expect(CoachChatIntent.inferredMealQuery(from: "previous meals from other days")?.queryType == .usualForBucket)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "HRV this week")?.queryType == .range)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "How did I sleep last night")?.queryType == .sleepDetail)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "How is my HRV today") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "What events do I have today")?.queryType == .today)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "Why am I marked busy")?.queryType == .today)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "What's on my calendar this week")?.queryType == .weekAhead)
        let tomorrow = CoachChatIntent.inferredCalendarQuery(from: "What do I have on tomorrow")
        #expect(tomorrow?.queryType == .day)
        #expect(tomorrow?.helmDay != nil)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "TRIMP history")?.queryType == .trimp)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "How has my weight trended")?.queryType == .weight)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "My e1rm progression")?.queryType == .e1rm)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "Energy balance history")?.queryType == .energyBalance)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "Readiness over time")?.queryType == .readiness)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "My trends")?.queryType == .all)
        let yesterday = CoachChatIntent.inferredWorkoutQuery(from: "Can you see the run I logged yesterday")
        #expect(yesterday?.queryType == .onDay)
        #expect(yesterday?.helmDay != nil)
        #expect(CoachChatIntent.looksLikeClearChat("clear chat"))
        #expect(!CoachChatIntent.looksLikeClearChat("clear my plate"))
    }

    // MARK: - Nutrition lookup

    @Test("looksLikeNutritionLookup detects nutrition-related phrases")
    func detectsNutritionLookup() {
        // Positive cases.
        #expect(CoachChatIntent.looksLikeNutritionLookup("What's my TDEE"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("what is my tdee"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("What should my macros be"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("macro target today"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("show me my weekly budget"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("calorie target"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("how many calories today"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("what can i eat today"))
    }

    @Test("session adjustment intent is exercise-level, not plan or food")
    func sessionAdjustmentIntent() {
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Swap bench for dumbbell press"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Add a set to RDL"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Take 5kg off the squat"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("Start the workout"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("How was my workout earlier"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("What's my TDEE"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("Swap my training plan to 4 days"))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach("Swap bench for incline", sessionIsLive: true))
        #expect(!CoachChatIntent.shouldRouteChatToSessionCoach("Swap bench for incline", sessionIsLive: false))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach(
            "Swap bench for incline on today's session",
            sessionIsLive: false
        ))
    }

    @Test("looksLikeNutritionLookup does not match unrelated phrases")
    func doesNotDetectNonNutritionPhrases() {
        // Negative cases.
        #expect(!CoachChatIntent.looksLikeNutritionLookup("log 300g of chicken"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("What should I do for my workout today"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("How was my sleep last night"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("add breakfast"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("yesterday I had 2000 calories"))
    }

    @Test("inferredNutritionQuery returns weeklyBudget for budget keywords and today otherwise")
    func infersNutritionQuery() {
        let budget = CoachChatIntent.inferredNutritionQuery(from: "Show me my weekly budget")
        #expect(budget?.queryType == .weeklyBudget)

        let week = CoachChatIntent.inferredNutritionQuery(from: "What's my nutrition budget")
        #expect(week?.queryType == .weeklyBudget)

        let weekAhead = CoachChatIntent.inferredNutritionQuery(from: "Plan my week ahead nutrition")
        #expect(weekAhead?.queryType == .weeklyBudget)

        let today = CoachChatIntent.inferredNutritionQuery(from: "What's my TDEE")
        #expect(today?.queryType == .today)

        let macros = CoachChatIntent.inferredNutritionQuery(from: "What should my macros be")
        #expect(macros?.queryType == .today)

        let history = CoachChatIntent.inferredNutritionQuery(from: "calorie history")
        #expect(history?.queryType == .range)

        let weeklyHistory = CoachChatIntent.inferredNutritionQuery(from: "weekly calorie history")
        #expect(weeklyHistory?.queryType == .range)

        let pastIntake = CoachChatIntent.inferredNutritionQuery(from: "past intake")
        #expect(pastIntake?.queryType == .range)

        let nilQuery = CoachChatIntent.inferredNutritionQuery(from: "log breakfast")
        #expect(nilQuery == nil)
    }
}

@Suite("CoachThreadState")
struct CoachThreadStateTests {
    @Test("windows to most recent messages")
    func windowsMessages() {
        let messages = (0 ..< 25).map { CoachMessage(role: .user, text: "m\($0)") }
        let windowed = CoachThreadState(messages: messages).windowed(limit: 20)
        #expect(windowed.messages.count == 20)
        #expect(windowed.messages.first?.text == "m5")
        #expect(windowed.messages.last?.text == "m24")
    }
}

@Suite("CoachTranscriptBuilder")
struct CoachTranscriptBuilderTests {
    @Test("does not duplicate trailing user message")
    func dropsTrailingDuplicate() {
        let thread = CoachThreadState(messages: [
            CoachMessage(role: .user, text: "hello"),
            CoachMessage(role: .assistant, text: "hi"),
            CoachMessage(role: .user, text: "start it")
        ])
        let contents = CoachTranscriptBuilder.contents(
            systemInstructions: "sys",
            contextBlock: "",
            userMessage: "start it",
            thread: thread
        )
        let userTexts = contents.compactMap { row -> String? in
            guard row["role"] as? String == "user",
                  let parts = row["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String
            else { return nil }
            return text
        }
        #expect(userTexts.filter { $0 == "start it" }.count == 1)
        #expect(userTexts.contains("hello"))
    }
}

@Suite("WorkoutStartStructuredPayload")
struct WorkoutStartStructuredPayloadTests {
    @Test("embeds start json for parser")
    func embedsJSON() throws {
        let payload = WorkoutStartStructuredPayload(
            reply: "Starting pull.",
            helmDay: "2026-08-03",
            title: "Pull",
            exercises: [
                .init(
                    name: "Lat Pulldown",
                    restSeconds: 90,
                    sets: [.init(setType: "normal", reps: 8, massKg: 52.5, rpe: 8)]
                )
            ]
        )
        let text = try payload.chatAssemblyText()
        #expect(text.hasPrefix("Starting pull."))
        #expect(text.contains("\"schemaVersion\":\"workout_start.v2\""))
        #expect(text.contains("Lat Pulldown"))
    }
}
