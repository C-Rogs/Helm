import Core
import Testing

@Suite("Meal portion assist context")
struct MealPortionAssistContextTests {
    @Test("vision prompt describes depth and scale direction")
    func visionPrompt() {
        let assist = MealPortionAssistContext(
            gramScaleFactor: 0.9,
            medianDepthMeters: 0.36,
            referenceDepthMeters: 0.32
        )
        let prompt = assist.visionPromptContext
        #expect(prompt.contains("LiDAR depth assist"))
        #expect(prompt.contains("36cm"))
        #expect(prompt.contains("smaller"))
    }
}
