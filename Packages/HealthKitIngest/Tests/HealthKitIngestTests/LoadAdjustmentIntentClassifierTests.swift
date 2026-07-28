import CoachLLM
import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Load adjustment intent")
struct LoadAdjustmentIntentClassifierTests {
    @Test("explicit mass instruction is user-directed")
    func explicitMass() {
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Add 10 kg to bench") == .userDirected)
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Set bench to 100 kg") == .userDirected)
        #expect(LoadAdjustmentIntentClassifier.intent(for: "+10 kg") == .userDirected)
    }

    @Test("directional commands are user-directed")
    func directionalCommands() {
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Go heavier on bench") == .userDirected)
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Drop weight, shoulder feels off") == .userDirected)
    }

    @Test("affirmations are user-directed")
    func affirmations() {
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Yes") == .userDirected)
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Do it") == .userDirected)
    }

    @Test("coach-style suggestion without athlete load instruction stays coach-suggested")
    func coachSuggestion() {
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Warm-up felt easy") == .coachSuggested)
        #expect(LoadAdjustmentIntentClassifier.intent(for: "Bump bench a little") == .coachSuggested)
    }

    @Test("stamper writes intent onto adjustLoad operations")
    func stamperWritesIntent() {
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Done.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: 10
                )
            ]
        )

        let stamped = LoadAdjustmentIntentClassifier.stamp(
            payload: payload,
            userMessage: "Add 10 kg"
        )

        #expect(stamped.operations[0].loadAdjustmentIntent == .userDirected)
    }

    @Test("stamper preserves intent when user message is absent")
    func stamperPreservesStoredIntent() {
        let payload = SessionAdjustmentPayload(
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            reply: "Done.",
            operations: [
                SessionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: 10,
                    loadAdjustmentIntent: .userDirected
                )
            ]
        )

        let stamped = LoadAdjustmentIntentClassifier.stamp(payload: payload, userMessage: nil)
        #expect(stamped.operations[0].loadAdjustmentIntent == .userDirected)
    }
}
