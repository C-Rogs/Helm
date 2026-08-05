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
        #expect(prompt.contains("workout_start.v2"))
        #expect(prompt.contains("never say \"Ready when you are\""))
        #expect(prompt.contains("confirm card"))
    }

    @Test("forbids evidence leaks and fake retention excuses")
    func antiHallucinationRules() {
        let prompt = CoachSystemPrompt.chatV1
        #expect(prompt.contains("ev-readiness-arc") || prompt.contains("internal evidence IDs"))
        #expect(prompt.contains("database retention") || prompt.contains("memory index unavailable"))
        #expect(prompt.contains("workout_query.v1"))
        #expect(prompt.contains("meal_query.v1"))
        #expect(prompt.contains("recovery_query.v1"))
        #expect(prompt.contains("memory_adjustment.v1"))
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
    }
}
