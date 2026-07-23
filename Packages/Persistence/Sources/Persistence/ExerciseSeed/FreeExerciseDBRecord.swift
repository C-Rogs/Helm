import Foundation

struct FreeExerciseDBRecord: Decodable, Sendable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]?
    let category: String?
    let images: [String]?
}

enum FreeExerciseCatalogSupport {
    private static let imageBaseURL = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

    static func decodeCatalog(from data: Data) throws -> [FreeExerciseDBRecord] {
        try JSONDecoder().decode([FreeExerciseDBRecord].self, from: data)
    }

    static func instructionText(for record: FreeExerciseDBRecord) -> String? {
        guard let steps = record.instructions, !steps.isEmpty else { return nil }
        return steps.joined(separator: "\n\n")
    }

    static func imageURL(for record: FreeExerciseDBRecord) -> String? {
        guard let path = record.images?.first, !path.isEmpty else { return nil }
        return imageBaseURL + path
    }
}
