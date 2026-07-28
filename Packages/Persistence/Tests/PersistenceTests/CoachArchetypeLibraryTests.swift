import Core
import Foundation
import Persistence
import Testing

@Suite("CoachArchetypeLibrary")
struct CoachArchetypeLibraryTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("bundled catalog decodes from app exercise seed")
    func bundledCatalogDecodes() throws {
        let catalogURL = repoRoot()
            .appendingPathComponent("Helm/Resources/ExerciseSeed/coach_archetype_catalog.json")

        let catalog = try CoachArchetypeLibrary.load(from: catalogURL)

        #expect(catalog.schemaVersion == "coach_archetype_catalog.v1")
        #expect(catalog.archetypes.count >= 80)
        #expect(catalog.mapping.count >= 873)
        #expect(catalog.validation?.mappingCoveragePercent == 100)
    }

    @Test("mapping covers every free-exercise-db ID")
    func mappingCoversCatalog() throws {
        let root = repoRoot()
        let catalogURL = root
            .appendingPathComponent("Helm/Resources/ExerciseSeed/coach_archetype_catalog.json")
        let freeExerciseURL = root
            .appendingPathComponent("Helm/Resources/ExerciseSeed/free-exercise-db.json")

        let archetypeCatalog = try CoachArchetypeLibrary.load(from: catalogURL)
        let freeExerciseData = try Data(contentsOf: freeExerciseURL)
        let records = try JSONDecoder().decode([FreeExerciseRecord].self, from: freeExerciseData)

        let missing = records.map(\.id).filter { archetypeCatalog.mapping[$0] == nil }
        #expect(missing.isEmpty)
    }
}

private struct FreeExerciseRecord: Decodable {
    let id: String
}
