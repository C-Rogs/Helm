import Foundation

struct ExerciseSeedMergeResult: Sendable, Equatable {
    let entries: [ExerciseSeedEntry]
    let explicitPickerIDs: Set<String>
    let overlayResolvedIDs: Set<String>
}

enum ExerciseSeedMerger {
    static func merge(catalog: [ExerciseSeedEntry], overlay: [ExerciseSeedEntry]) -> ExerciseSeedMergeResult {
        guard !overlay.isEmpty else {
            return ExerciseSeedMergeResult(
                entries: catalog,
                explicitPickerIDs: [],
                overlayResolvedIDs: []
            )
        }

        var byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var byCanonical: [String: ExerciseSeedEntry] = [:]
        for entry in catalog {
            let key = normalizeCanonical(entry.canonicalName)
            if byCanonical[key] == nil {
                byCanonical[key] = entry
            }
        }
        var bySource: [String: ExerciseSeedEntry] = [:]
        for entry in catalog {
            if let sourceID = entry.sourceDatasetID {
                bySource[sourceID] = entry
            }
        }

        var explicitPickerIDs = Set<String>()
        var overlayResolvedIDs = Set<String>()

        for overlayEntry in overlay {
            let targetID: String
            if let sourceID = overlayEntry.sourceDatasetID, let match = bySource[sourceID] {
                targetID = match.id
            } else if let match = byCanonical[normalizeCanonical(overlayEntry.canonicalName)] {
                targetID = match.id
            } else {
                targetID = overlayEntry.id
            }

            let base = byID[targetID] ?? overlayEntry
            let merged = mergeEntry(base: base, overlay: overlayEntry, resolvedID: targetID)
            byID[targetID] = merged
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
        resolvedID: String
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
            instructionText: overlay.instructionText ?? base.instructionText,
            coachingCues: mergedCoachingCues(base: base.coachingCues, overlay: overlay.coachingCues),
            imageURL: overlay.imageURL ?? base.imageURL,
            isPickerDefault: overlay.isPickerDefault ?? base.isPickerDefault,
            isHevyLibrary: overlay.isHevyLibrary ?? base.isHevyLibrary,
            evidence: overlay.evidence ?? base.evidence
        )
    }

    private static func mergedCoachingCues(base: [String]?, overlay: [String]?) -> [String]? {
        if let overlay, !overlay.isEmpty { return overlay }
        if let base, !base.isEmpty { return base }
        return nil
    }

    private static func normalizeCanonical(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
