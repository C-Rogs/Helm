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

    @Test("JSON-only workout_start leaves empty user-facing text")
    func jsonOnlyWorkoutStartIsEmpty() {
        let text = """
        {"schemaVersion":"workout_start.v2","helmDay":"2026-07-31","title":"Push","exercises":[{"name":"Bench Press","sets":[{"setType":"normal","reps":8,"massKg":80}]}]}
        """
        let formatted = CoachChatTextFormatter.userFacingText(from: text)
        #expect(formatted.isEmpty)
    }

    @Test("extracts evidence, topic, and engine source tags")
    func extractsSourceTags() {
        let text = """
        Rest for 180s between compound sets [ev-hypertrophy-session-design-2].
        See also [topic:hypertrophy-volume-landmarks] for more.
        The engine targets 10-20 weekly sets [engine:progression].
        """
        let tags = CoachChatTextFormatter.sourceTags(from: text)
        #expect(tags.count == 3)

        let evidenceTag = tags.first(where: { $0.kind == .evidence })
        #expect(evidenceTag?.rawID == "ev-hypertrophy-session-design-2")

        let topicTag = tags.first(where: { $0.kind == .topic })
        #expect(topicTag?.rawID == "topic:hypertrophy-volume-landmarks")

        let engineTag = tags.first(where: { $0.kind == .engine })
        #expect(engineTag?.rawID == "engine:progression")
        #expect(engineTag?.display == "Prescription Engine")
    }

    @Test("deduplicates repeated evidence IDs")
    func deduplicatesSourceTags() {
        let text = "Cite [ev-hypertrophy-volume-landmarks] again [ev-hypertrophy-volume-landmarks]."
        let tags = CoachChatTextFormatter.sourceTags(from: text)
        #expect(tags.count == 1)
    }
}
