import CoachLLM
import Core
import Foundation

enum LoadAdjustmentIntentClassifier {
    static func intent(for userMessage: String) -> LoadAdjustmentIntent {
        let normalized = userMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .coachSuggested }

        if containsExplicitLoadInstruction(normalized) {
            return .userDirected
        }
        if containsAffirmation(normalized) {
            return .userDirected
        }
        if containsDirectionalWeightCommand(normalized) {
            return .userDirected
        }
        return .coachSuggested
    }

    static func stamp(
        payload: SessionAdjustmentPayload,
        userMessage: String?
    ) -> SessionAdjustmentPayload {
        let turnIntent: LoadAdjustmentIntent? = userMessage.map(intent(for:))
        let operations = payload.operations.map { operation in
            stamp(operation: operation, turnIntent: turnIntent)
        }
        return SessionAdjustmentPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            rationale: payload.rationale,
            operations: operations
        )
    }

    private static func stamp(
        operation: SessionAdjustmentOperation,
        turnIntent: LoadAdjustmentIntent?
    ) -> SessionAdjustmentOperation {
        guard operation.kind == .adjustLoad else { return operation }

        let resolvedIntent = turnIntent ?? operation.loadAdjustmentIntent ?? .coachSuggested
        return SessionAdjustmentOperation(
            kind: operation.kind,
            fromExerciseID: operation.fromExerciseID,
            toExerciseID: operation.toExerciseID,
            excludeExerciseIDs: operation.excludeExerciseIDs,
            orderedExerciseIDs: operation.orderedExerciseIDs,
            exerciseID: operation.exerciseID,
            setDelta: operation.setDelta,
            massDeltaKg: operation.massDeltaKg,
            targetMassKg: operation.targetMassKg,
            rpeDelta: operation.rpeDelta,
            targetRPE: operation.targetRPE,
            loadAdjustmentIntent: resolvedIntent
        )
    }

    private static func containsExplicitLoadInstruction(_ message: String) -> Bool {
        let patterns = [
            #"\d+(?:\.\d+)?\s*(?:kg|kgs|kilo?s|lb|lbs|pounds?)"#,
            #"[+-]\s*\d+(?:\.\d+)?"#,
            #"(?:add|drop|strip|remove|take off|bump|increase|decrease|lower|raise)\s+\d+(?:\.\d+)?"#,
            #"(?:set|make|put)\b.{0,40}?\b(?:to|at)\s+\d+(?:\.\d+)?"#,
            #"\b\d+(?:\.\d+)?\s*(?:kg|kgs)\b"#,
            #"\b(?:plate|plates)\b"#
        ]
        return patterns.contains { pattern in
            message.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func containsAffirmation(_ message: String) -> Bool {
        let affirmations = [
            "yes",
            "yep",
            "yeah",
            "sure",
            "ok",
            "okay",
            "do it",
            "go ahead",
            "sounds good",
            "let's do it",
            "lets do it"
        ]
        let trimmed = message.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return affirmations.contains(trimmed)
    }

    private static func containsDirectionalWeightCommand(_ message: String) -> Bool {
        let phrases = [
            "heavier",
            "lighter",
            "more weight",
            "less weight",
            "go heavier",
            "go lighter",
            "add weight",
            "drop weight",
            "take weight off"
        ]
        return phrases.contains { message.contains($0) }
    }
}
