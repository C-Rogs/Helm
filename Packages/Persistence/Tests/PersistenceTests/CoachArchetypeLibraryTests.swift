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
        #expect(catalog.archetypes.count >= 50)
        #expect(catalog.mapping.count >= 100)
        #expect(catalog.validation?.mappingCoveragePercent == 100)
    }

    @Test("mapping targets known archetypes")
    func mappingTargetsKnownArchetypes() throws {
        let catalogURL = repoRoot()
            .appendingPathComponent("Helm/Resources/ExerciseSeed/coach_archetype_catalog.json")
        let catalog = try CoachArchetypeLibrary.load(from: catalogURL)
        let ids = Set(catalog.archetypes.map(\.id))
        let dangling = catalog.mapping.filter { !ids.contains($0.value) }.map(\.key)
        #expect(dangling.isEmpty)
    }
}
