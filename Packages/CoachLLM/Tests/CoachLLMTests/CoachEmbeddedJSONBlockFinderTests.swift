import Foundation
import Testing
@testable import CoachLLM

@Suite("CoachEmbeddedJSONBlockFinder")
struct CoachEmbeddedJSONBlockFinderTests {
    @Test("finds workout_start block when trailing prose contains braces")
    func findsBlockWithTrailingBraces() {
        let text = """
        Ready.
        {"schemaVersion":"workout_start.v1","helmDay":"2026-07-29","useAdjustedPrescription":false}
        Keep rest {short}.
        """
        let block = CoachEmbeddedJSONBlockFinder.firstBlock(
            in: text,
            matching: .workoutStartV1
        )
        #expect(block?.contains("workout_start.v1") == true)
        #expect(block?.contains("short") == false)
    }

    @Test("prefers fenced workout_start v2 block")
    func findsFencedV2Block() {
        let text = """
        Starting now.

        ```json
        {"schemaVersion":"workout_start.v2","helmDay":"2026-07-29","exercises":[{"name":"Bench Press","sets":[{"setType":"warmup","reps":10,"massKg":60}]}]}
        ```
        """
        let block = CoachEmbeddedJSONBlockFinder.firstBlock(
            in: text,
            matching: .workoutStartV2
        )
        #expect(block?.contains("workout_start.v2") == true)
    }
}

@Suite("CoachChatTextFormatter")
struct CoachChatTextFormatterTests {
    @Test("strips workout_start JSON from assistant text")
    func stripsWorkoutStartJSON() {
        let text = """
        Starting your session now.

        {"schemaVersion":"workout_start.v2","helmDay":"2026-07-29","exercises":[{"name":"Bench Press","sets":[{"setType":"normal","reps":8,"massKg":80}]}]}
        """
        let formatted = CoachChatTextFormatter.userFacingText(from: text)
        #expect(formatted == "Starting your session now.")
        #expect(!formatted.contains("schemaVersion"))
    }
}
