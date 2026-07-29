import Foundation

public enum ExerciseCoachingCuePicker {
    public static func cue(
        coachingCues: [String],
        instructionText: String?,
        exerciseID: String,
        sessionID: String
    ) -> String? {
        let candidates: [String]
        if !coachingCues.isEmpty {
            candidates = coachingCues
        } else if let instructionText {
            candidates = instructionCues(from: instructionText)
        } else {
            return nil
        }
        guard !candidates.isEmpty else { return nil }

        let seed = abs((exerciseID + sessionID).hashValue)
        return candidates[seed % candidates.count]
    }

    private static func instructionCues(from instructionText: String) -> [String] {
        instructionText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 12 }
    }
}
