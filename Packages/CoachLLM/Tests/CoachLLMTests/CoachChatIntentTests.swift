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
