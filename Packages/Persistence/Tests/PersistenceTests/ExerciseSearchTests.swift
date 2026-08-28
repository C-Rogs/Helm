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

    @Test("equipment-preserving normalize keeps cable vs dumbbell distinct")
    func keepsEquipmentTokens() {
        #expect(
            ExerciseSearchNormalizer.normalizeKeepingEquipment("Hammer Curl (Cable)")
                == "hammer curl cable"
        )
        #expect(
            ExerciseSearchNormalizer.normalizeKeepingEquipment("Hammer Curl (Dumbbell)")
                == "hammer curl dumbbell"
        )
        #expect(
            ExerciseSearchNormalizer.normalizeKeepingEquipment("hammer curls rope")
                == "hammer curls cable"
        )
        #expect(ExerciseSearchNormalizer.synonym("dumbbells") == "dumbbell")
        #expect(ExerciseSearchNormalizer.synonym("rope") == "cable")
        #expect(ExerciseSearchNormalizer.synonym("bb") == "barbell")
        #expect(ExerciseSearchNormalizer.synonym("kb") == "kettlebell")
        #expect(ExerciseSearchNormalizer.synonym("cables") == "cable")
        #expect(
            ExerciseSearchNormalizer.normalizeKeepingEquipment("BB RDL")
                == "barbell rdl"
        )
        #expect(
            ExerciseSearchNormalizer.normalizeKeepingEquipment("kb swing")
                == "kettlebell swing"
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
    @Test("overlay keeps its own id and copies GIF from catalog source")
    func overlayKeepsOwnID() throws {
        let catalog = [
            ExerciseSeedEntry(
                id: "seed-Face_Pull",
                canonicalName: "face pull",
                displayName: "Face Pull",
                aliases: ["Face Pull"],
                exerciseMode: .weightReps,
                equipment: "cable",
                primaryMuscleGroup: "shoulders",
                sourceDatasetID: "Face_Pull",
                imageURL: "https://example.com/face-pull.gif"
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
        let overlayRow = try #require(merged.entries.first { $0.id == "seed-face-pull-overlay" })
        let catalogRow = try #require(merged.entries.first { $0.id == "seed-Face_Pull" })
        #expect(merged.entries.count == 2)
        #expect(overlayRow.imageURL == "https://example.com/face-pull.gif")
        #expect(catalogRow.displayName == "Face Pull")
        #expect(merged.explicitPickerIDs == ["seed-face-pull-overlay"])
    }

    @Test("shared sourceDatasetID does not collapse distinct overlay rows")
    func sharedSourceKeepsDistinctRows() {
        let catalog = [
            ExerciseSeedEntry(
                id: "seed-Cable_Hammer_Curls_-_Rope_Attachment",
                canonicalName: "cable hammer curls - rope attachment",
                displayName: "Cable Hammer Curls - Rope Attachment",
                aliases: [],
                exerciseMode: .weightReps,
                sourceDatasetID: "Cable_Hammer_Curls_-_Rope_Attachment",
                imageURL: "https://example.com/rope.gif"
            )
        ]
        let overlay = [
            ExerciseSeedEntry(
                id: "seed-cam-hammer-curl-cable",
                canonicalName: "hammer curl cable",
                displayName: "Hammer Curl (Cable)",
                aliases: ["Hammer Curl (Cable)"],
                exerciseMode: .weightReps,
                sourceDatasetID: "Cable_Hammer_Curls_-_Rope_Attachment",
                isPickerDefault: true
            ),
            ExerciseSeedEntry(
                id: "seed-cam-bicep-curl-cable",
                canonicalName: "bicep curl cable",
                displayName: "Bicep Curl (Cable)",
                aliases: ["Bicep Curl (Cable)"],
                exerciseMode: .weightReps,
                sourceDatasetID: "Cable_Hammer_Curls_-_Rope_Attachment",
                isPickerDefault: true
            )
        ]

        let merged = ExerciseSeedMerger.merge(catalog: catalog, overlay: overlay)
        #expect(merged.entries.contains { $0.id == "seed-cam-hammer-curl-cable" })
        #expect(merged.entries.contains { $0.id == "seed-cam-bicep-curl-cable" })
        #expect(merged.entries.contains { $0.id == "seed-Cable_Hammer_Curls_-_Rope_Attachment" })
        #expect(merged.explicitPickerIDs.count == 2)
    }

    @Test("overlay coaching cues replace catalog cues")
    func mergesCoachingCues() {
        let catalog = [
            ExerciseSeedEntry(
                id: "seed-bench-press",
                canonicalName: "bench press (barbell)",
                displayName: "Bench Press (Barbell)",
                aliases: [],
                exerciseMode: .weightReps,
                coachingCues: ["Old cue one is long.", "Old cue two is long."]
            )
        ]
        let overlay = [
            ExerciseSeedEntry(
                id: "seed-bench-press",
                canonicalName: "bench press (barbell)",
                displayName: "Bench Press (Barbell)",
                aliases: [],
                exerciseMode: .weightReps,
                coachingCues: ["Brace hard and pull shoulder blades together.", "Press up and slightly back."]
            )
        ]

        let merged = ExerciseSeedMerger.merge(catalog: catalog, overlay: overlay)
        #expect(merged.entries[0].coachingCues == overlay[0].coachingCues)
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
