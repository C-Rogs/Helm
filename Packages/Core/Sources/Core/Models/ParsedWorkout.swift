import Foundation

public struct ParsedWorkoutSet: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let setIndex: Int
    public let setType: SetType
    public let mass: Mass?
    public let reps: Int?
    public let rpe: Double?
    public let prescriptionNote: String?
    public let restDurationSeconds: Int?

    public init(
        id: String = UUID().uuidString,
        setIndex: Int,
        setType: SetType = .normal,
        mass: Mass? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        prescriptionNote: String? = nil,
        restDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.setIndex = setIndex
        self.setType = setType
        self.mass = mass
        self.reps = reps
        self.rpe = rpe
        self.prescriptionNote = prescriptionNote
        self.restDurationSeconds = restDurationSeconds
    }
}

public struct ParsedWorkoutExercise: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseTitle: String
    public let sets: [ParsedWorkoutSet]
    public let restDurationSeconds: Int?

    public init(
        id: String = UUID().uuidString,
        exerciseTitle: String,
        sets: [ParsedWorkoutSet],
        restDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.exerciseTitle = exerciseTitle
        self.sets = sets
        self.restDurationSeconds = restDurationSeconds
    }
}

public struct ParsedWorkout: Sendable, Hashable, Codable {
    public let title: String
    public let exercises: [ParsedWorkoutExercise]
    public let skippedLines: [String]

    public init(
        title: String,
        exercises: [ParsedWorkoutExercise],
        skippedLines: [String] = []
    ) {
        self.title = title
        self.exercises = exercises
        self.skippedLines = skippedLines
    }
}

public enum ParsedWorkoutTitle {
    /// Strips trailing parenthetical coaching notes for catalog matching.
    public static func catalogMatchTitle(from displayTitle: String) -> String {
        let text = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else {
            return text
        }
        let candidate = String(text[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        return candidate.isEmpty ? text : candidate
    }
}
