import Foundation

enum ExerciseCoachingCuePicker {
    static func cue(
        instructionText: String?,
        exerciseID: String,
        sessionID: String
    ) -> String? {
        guard let instructionText else { return nil }
        let cues = instructionText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 12 }
        guard !cues.isEmpty else { return nil }

        let seed = abs((exerciseID + sessionID).hashValue)
        return cues[seed % cues.count]
    }
}
