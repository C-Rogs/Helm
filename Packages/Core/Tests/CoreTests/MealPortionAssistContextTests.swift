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
        #expect(assist.measurementLine == "36 cm away")
    }

    @Test("measurement line includes center span when known")
    func measurementLineWithSpan() {
        let assist = MealPortionAssistContext(
            gramScaleFactor: 1,
            medianDepthMeters: 0.27,
            referenceDepthMeters: 0.32,
            centerSpanCentimeters: 14.2
        )
        #expect(assist.measurementLine == "27 cm away · 14 cm across")
        #expect(assist.visionPromptContext.contains("14cm across"))
    }

    @Test("center span scales focal length into depth-map pixels")
    func centerSpanMath() {
        let sameScale = MealDepthSpan.centerSpanCentimeters(
            depthMapWidthPixels: 100,
            focalLengthPixels: 50,
            intrinsicReferenceWidthPixels: 100,
            depthMeters: 0.27
        )
        #expect(abs((sameScale ?? 0) - 21.6) < 0.001)

        let downscaledMap = MealDepthSpan.centerSpanCentimeters(
            depthMapWidthPixels: 100,
            focalLengthPixels: 50,
            intrinsicReferenceWidthPixels: 200,
            depthMeters: 0.27
        )
        #expect(abs((downscaledMap ?? 0) - 43.2) < 0.001)

        #expect(
            MealDepthSpan.centerSpanCentimeters(
                depthMapWidthPixels: 0,
                focalLengthPixels: 50,
                intrinsicReferenceWidthPixels: 100,
                depthMeters: 0.27
            ) == nil
        )
    }

}
