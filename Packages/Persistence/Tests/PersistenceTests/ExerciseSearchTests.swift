import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Exercise search normalizer")
struct ExerciseSearchNormalizerTests {
    @Test("strips equipment parenthetical and normalizes word order")
    func normalizesTitles() {
        #expect(
            ExerciseSearchNormalizer.normalize("Leg Press Horizontal (Machine)")
                == "leg press horizontal"
        )
        #expect(
            ExerciseSearchNormalizer.normalize("Horizontal Leg Press")
                == "horizontal leg press"
        )
    }

    @Test("search candidates include sorted token variant")
    func searchCandidates() {
        let candidates = ExerciseSearchNormalizer.searchCandidates(for: "Leg Press Horizontal")
        #expect(candidates.contains("leg press horizontal"))
        #expect(candidates.contains("horizontal leg press"))
    }
}

@Suite("Exercise seed merger")
struct ExerciseSeedMergerTests {
    @Test("overlay merges into catalog row by sourceDatasetID")
    func mergesBySourceID() throws {
        let catalog = [
            ExerciseSeedEntry(
                id: "seed-Face_Pull",
                canonicalName: "face pull",
                displayName: "Face Pull (Cable)",
                aliases: ["Face Pull"],
                exerciseMode: .weightReps,
                equipment: "cable",
                primaryMuscleGroup: "shoulders",
                sourceDatasetID: "Face_Pull"
            )
        ]
        let overlay = [
            ExerciseSeedEntry(
                id: "seed-face-pull-overlay",
                canonicalName: "cable face pull",
                displayName: "Face Pull (Cable)",
                aliases: ["Face Pull (Cable)", "Cable Face Pull"],
                exerciseMode: .weightReps,
                equipment: "cable",
                primaryMuscleGroup: "shoulders",
                sourceDatasetID: "Face_Pull",
                isPickerDefault: true,
                isHevyLibrary: true
            )
        ]

        let merged = ExerciseSeedMerger.merge(catalog: catalog, overlay: overlay)
        #expect(merged.entries.count == 1)
        #expect(merged.entries[0].id == "seed-Face_Pull")
        #expect(merged.entries[0].aliases.contains("Cable Face Pull"))
        #expect(merged.explicitPickerIDs == ["seed-Face_Pull"])
    }

    @Test("overlay appends when no catalog match")
    func appendsUnmatchedOverlay() {
        let overlay = [
            ExerciseSeedEntry(
                id: "seed-horizontal-leg-press",
                canonicalName: "horizontal leg press",
                displayName: "Leg Press Horizontal (Machine)",
                aliases: ["Leg Press Horizontal (Machine)"],
                exerciseMode: .weightReps,
                equipment: "machine",
                primaryMuscleGroup: "quadriceps",
                isPickerDefault: true
            )
        ]

        let merged = ExerciseSeedMerger.merge(catalog: [], overlay: overlay)
        #expect(merged.entries.count == 1)
        #expect(merged.entries[0].displayName == "Leg Press Horizontal (Machine)")
        #expect(merged.explicitPickerIDs.contains("seed-horizontal-leg-press"))
    }
}
