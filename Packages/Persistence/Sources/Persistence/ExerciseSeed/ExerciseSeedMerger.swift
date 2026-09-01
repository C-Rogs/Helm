import Foundation

struct ExerciseSeedMergeResult: Sendable, Equatable {
    let entries: [ExerciseSeedEntry]
    let explicitPickerIDs: Set<String>
    let overlayResolvedIDs: Set<String>
}

enum ExerciseSeedMerger {
    /// Overlay rows keep their own ids. `sourceDatasetID` only copies GIF /
    /// instructions off the Free Exercise DB row so hide-lists cannot delete
    /// the Hevy-named overlay.
    static func merge(catalog: [ExerciseSeedEntry], overlay: [ExerciseSeedEntry]) -> ExerciseSeedMergeResult {
        guard !overlay.isEmpty else {
            return ExerciseSeedMergeResult(
                entries: catalog,
                explicitPickerIDs: [],
                overlayResolvedIDs: []
            )
        }

        var byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var bySource: [String: ExerciseSeedEntry] = [:]
        for entry in catalog {
            if let sourceID = entry.sourceDatasetID {
                bySource[sourceID] = entry
            }
        }

        var explicitPickerIDs = Set<String>()
        var overlayResolvedIDs = Set<String>()

        for overlayEntry in overlay {
            let targetID = overlayEntry.id
            let catalogMedia: ExerciseSeedEntry? = overlayEntry.sourceDatasetID.flatMap { bySource[$0] }
            let base = byID[targetID] ?? overlayEntry
            byID[targetID] = mergeEntry(
                base: base,
                overlay: overlayEntry,
                resolvedID: targetID,
                catalogMedia: catalogMedia
            )
            overlayResolvedIDs.insert(targetID)

            if overlayEntry.isPickerDefault == true {
                explicitPickerIDs.insert(targetID)
            }
        }

        return ExerciseSeedMergeResult(
            entries: Array(byID.values),
            explicitPickerIDs: explicitPickerIDs,
            overlayResolvedIDs: overlayResolvedIDs
        )
    }

    private static func mergeEntry(
        base: ExerciseSeedEntry,
        overlay: ExerciseSeedEntry,
        resolvedID: String,
        catalogMedia: ExerciseSeedEntry?
    ) -> ExerciseSeedEntry {
        var aliases = base.aliases
        for alias in overlay.aliases where !aliases.contains(alias) {
            aliases.append(alias)
        }

        return ExerciseSeedEntry(
            id: resolvedID,
            canonicalName: overlay.canonicalName.isEmpty ? base.canonicalName : overlay.canonicalName,
            displayName: overlay.displayName.isEmpty ? base.displayName : overlay.displayName,
            aliases: aliases,
            exerciseMode: overlay.exerciseMode,
            equipment: overlay.equipment ?? base.equipment,
            primaryMuscleGroup: overlay.primaryMuscleGroup ?? base.primaryMuscleGroup,
            secondaryMuscleGroups: overlay.secondaryMuscleGroups.isEmpty
                ? base.secondaryMuscleGroups
                : overlay.secondaryMuscleGroups,
            movementPattern: overlay.movementPattern ?? base.movementPattern,
            sourceDatasetID: overlay.sourceDatasetID ?? base.sourceDatasetID,
            instructionText: overlay.instructionText ?? catalogMedia?.instructionText ?? base.instructionText,
            coachingCues: mergedCoachingCues(base: base.coachingCues, overlay: overlay.coachingCues),
            imageURL: overlay.imageURL ?? catalogMedia?.imageURL ?? base.imageURL,
            isPickerDefault: overlay.isPickerDefault ?? base.isPickerDefault,
            pickerRank: overlay.pickerRank ?? base.pickerRank,
            isHevyLibrary: overlay.isHevyLibrary ?? base.isHevyLibrary,
            evidence: overlay.evidence ?? base.evidence
        )
    }

    private static func mergedCoachingCues(base: [String]?, overlay: [String]?) -> [String]? {
        if let overlay, !overlay.isEmpty { return overlay }
        if let base, !base.isEmpty { return base }
        return nil
    }
}
