import CoachLLM
import Testing

@Suite("CoachSystemPrompt")
struct CoachSystemPromptTests {
    @Test("food dictation coach message frames transcript without changing stored text contract")
    func foodDictationCoachMessage() {
        let message = CoachSystemPrompt.foodDictationCoachMessage(transcript: "two eggs and toast for breakfast")
        #expect(message.contains("Food dictation"))
        #expect(message.contains("two eggs and toast for breakfast"))
        #expect(CoachSystemPrompt.chatV1.contains("Spoken or dictated meal reports"))
    }

    @Test("chat voice is conversational, not brief-style metric dumps or sentence quotas")
    func chatVoiceRules() {
        let prompt = CoachSystemPrompt.chatV1
        #expect(prompt.contains("chat-length"))
        #expect(prompt.contains("morning-brief-style metric list") || prompt.contains("morning-brief-style"))
        #expect(!prompt.contains("Be terse, numbers-first"))
        #expect(!prompt.contains("numbers matter in prose"))
        #expect(prompt.contains("Never use em dashes"))
        #expect(!prompt.contains("2-6 sentences"))
        #expect(!prompt.contains("Prefer 2"))
    }

    @Test("workout negotiation before structured start")
    func workoutNegotiation() {
        let prompt = CoachSystemPrompt.chatV1
        #expect(prompt.contains("Negotiate openly"))
        #expect(prompt.contains("workout_start"))
        #expect(prompt.contains("never say \"Ready when you are\""))
        #expect(prompt.contains("confirm card"))
    }

    @Test("forbids evidence leaks and fake retention excuses")
    func antiHallucinationRules() {
        let prompt = CoachSystemPrompt.chatV1
        #expect(prompt.contains("ev-readiness-arc") || prompt.contains("internal evidence IDs"))
        #expect(prompt.contains("database retention") || prompt.contains("memory index unavailable"))
        #expect(prompt.contains("workout_query"))
        #expect(prompt.contains("meal_query"))
        #expect(prompt.contains("recovery_query"))
        #expect(prompt.contains("Readiness Baselines dates for weight and body fat"))
        #expect(prompt.contains("calendar_query"))
        #expect(prompt.contains("lookaheadDays"))
        #expect(prompt.contains("optional search"))
        #expect(prompt.contains("trends_query"))
        #expect(prompt.contains("call the workout_query tool"))
        #expect(prompt.contains("call the trends_query tool"))
        #expect(prompt.contains("queryType bodyFat"))
        #expect(prompt.contains("call the meal_query tool"))
        #expect(prompt.contains("call the context_refresh tool") || prompt.contains("Call the context_refresh tool"))
        #expect(prompt.contains("call the chart tool"))
        #expect(prompt.contains("Call navigate when"))
        #expect(prompt.contains("append navigate.v1 JSON"))
        #expect(prompt.contains("memory_adjustment"))
        #expect(prompt.contains("Prescription Load Rationale"))
        #expect(prompt.contains("constraint_affected=true"))
        #expect(prompt.contains("load_decision"))
        #expect(prompt.contains("call the food_log tool"))
        #expect(prompt.contains("health_sync"))
        #expect(prompt.contains("history and trends only"))
        #expect(prompt.contains("Do not embed those as JSON"))
        #expect(prompt.contains("App State"))
        #expect(prompt.contains("nutrition_day"))
        #expect(prompt.contains("Apply change card"))
        #expect(!prompt.contains("Train Discuss sheet"))
    }

    @Test("in-session coach shares main chat voice")
    func inSessionSharesMainVoice() {
        let prompt = CoachSystemPrompt.sessionAdjustmentV2
        #expect(prompt.contains("same coach as in the main chat"))
        #expect(prompt.contains("chat-length"))
        #expect(prompt.contains("Never use em dashes"))
        #expect(prompt.contains("Never quote or paraphrase these voice instructions"))
        #expect(!prompt.contains("terse, numbers-first answer"))
        #expect(prompt.contains("current heart rate") || prompt.contains("logged sets"))
        #expect(prompt.contains("Available gym exercises") || prompt.contains("triceps_dip"))
        #expect(prompt.contains("exact display names") || prompt.contains("fromExerciseID must copy the archetypeId"))
        #expect(prompt.contains("does not need to already be in the active session"))
        #expect(prompt.contains("Never claim the swap already happened"))
    }
}
