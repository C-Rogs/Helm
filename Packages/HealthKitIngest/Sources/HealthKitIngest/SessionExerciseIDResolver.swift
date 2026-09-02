import CoachLLM
import Core
import Foundation
import Persistence

enum SessionExerciseIDResolver {
    struct Result: Sendable, Equatable {
        let payload: SessionAdjustmentPayload
        let unresolvedExerciseIDs: [String]
        let catalogCandidates: [String]
    }

    static func normalize(
        payload: SessionAdjustmentPayload,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String> = [],
        familiarExerciseIDs: Set<String> = [],
        recentExerciseIDs: Set<String> = [],
        phraseHint: String? = nil,
        orderedSessionExerciseIDs: [String] = []
    ) throws -> Result {
        var unresolved: [String] = []
        var catalogCandidates: [String] = []
        let addPhrases = SessionSwapPhrase.parseAddList(phraseHint)
        var addPhraseIndex = 0
        var addedThisPayload: Set<String> = []
        var mappedOps: [SessionAdjustmentOperation] = []

        for operation in payload.operations {
            if operation.kind == .addExercise {
                let span = addPhraseIndex < addPhrases.count ? addPhrases[addPhraseIndex] : nil
                addPhraseIndex += 1
                mappedOps.append(
                    mapOperation(
                        operation,
                        sessionExerciseIDs: sessionExerciseIDs,
                        exerciseDisplayNames: exerciseDisplayNames,
                        persistence: persistence,
                        excludedExerciseIDs: excludedExerciseIDs.union(addedThisPayload),
                        familiarExerciseIDs: familiarExerciseIDs,
                        recentExerciseIDs: recentExerciseIDs,
                        phraseHint: phraseHint,
                        replyHint: payload.reply,
                        addSpan: span,
                        restrictAddHintsToSpan: addPhrases.isEmpty == false,
                        unresolved: &unresolved,
                        catalogCandidates: &catalogCandidates
                    )
                )
                if let added = mappedOps.last?.toExerciseID {
                    addedThisPayload.insert(added)
                }
                continue
            }
            mappedOps.append(
                mapOperation(
                    operation,
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: excludedExerciseIDs,
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    phraseHint: phraseHint,
                    replyHint: payload.reply,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates
                )
            )
        }

        while addPhraseIndex < addPhrases.count {
            let span = addPhrases[addPhraseIndex]
            addPhraseIndex += 1
            mappedOps.append(
                mapOperation(
                    SessionAdjustmentOperation(kind: .addExercise, targetSets: 3),
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: excludedExerciseIDs.union(addedThisPayload),
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    phraseHint: phraseHint,
                    replyHint: payload.reply,
                    addSpan: span,
                    restrictAddHintsToSpan: true,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates
                )
            )
            if let added = mappedOps.last?.toExerciseID {
                addedThisPayload.insert(added)
            }
        }

        let swappedFrom = Set(mappedOps.compactMap { $0.kind == .swap ? $0.fromExerciseID : nil })
        let swappedTo = Set(mappedOps.compactMap { $0.kind == .swap ? $0.toExerciseID : nil })
        let expectedAfterMutations = Set(orderedSessionExerciseIDs)
            .subtracting(swappedFrom)
            .union(swappedTo)
            .union(addedThisPayload)

        let keptOps = mappedOps.filter { operation in
            guard operation.kind == .reorder else { return true }
            guard let ordered = operation.orderedExerciseIDs, !ordered.isEmpty else { return false }
            return Set(ordered) == expectedAfterMutations
        }
        let nonReorder = keptOps.filter { $0.kind != .reorder }
        let reorders = keptOps.filter { $0.kind == .reorder }
        let normalizedOps = nonReorder + reorders

        let withMove = applyRelativeMove(
            operations: normalizedOps,
            phraseHint: phraseHint,
            orderedSessionExerciseIDs: orderedSessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames
        )

        let normalized = SessionAdjustmentPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            rationale: payload.rationale,
            operations: withMove
        )

        return Result(
            payload: normalized,
            unresolvedExerciseIDs: Array(Set(unresolved)).sorted(),
            catalogCandidates: Array(Set(catalogCandidates)).sorted()
        )
    }

    private static func mapOperation(
        _ operation: SessionAdjustmentOperation,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        phraseHint: String?,
        replyHint: String?,
        addSpan: String? = nil,
        restrictAddHintsToSpan: Bool = false,
        unresolved: inout [String],
        catalogCandidates: inout [String]
    ) -> SessionAdjustmentOperation {
        switch operation.kind {
        case .swap:
            let parsed = phraseHint.flatMap { SessionSwapPhrase.parse($0) }
            let from = resolveSessionSource(
                modelID: operation.fromExerciseID,
                athleteFrom: parsed?.from,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            // Exclude the current slot so same-archetype equipment swaps (rope -> DB)
            // cannot collapse back onto the from ID when the user message still names it.
            var toExcluded = excludedExerciseIDs
            if let from {
                toExcluded.insert(from)
            }
            let to: String?
            if let from, let toPhrase = parsed?.to, ExerciseResolver.isEquipmentOnlyPhrase(toPhrase) {
                to = ExerciseResolver.pickEquipmentSibling(
                    of: from,
                    equipmentPhrase: toPhrase,
                    context: ExerciseResolver.Context(
                        sessionExerciseIDs: sessionExerciseIDs,
                        exerciseDisplayNames: exerciseDisplayNames,
                        excludedExerciseIDs: toExcluded,
                        familiarExerciseIDs: familiarExerciseIDs,
                        recentExerciseIDs: recentExerciseIDs,
                        mustBeInSession: false,
                        phraseHint: toPhrase
                    ),
                    persistence: persistence
                ) ?? resolveCatalogTarget(
                    modelID: operation.toExerciseID,
                    hints: [parsed?.to, phraseHint, replyHint],
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: toExcluded,
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates
                )
            } else {
                to = resolveCatalogTarget(
                    modelID: operation.toExerciseID,
                    hints: [parsed?.to, phraseHint, replyHint],
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: toExcluded,
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates
                )
            }
            return SessionAdjustmentOperation(
                kind: operation.kind,
                fromExerciseID: from,
                toExerciseID: to,
                excludeExerciseIDs: operation.excludeExerciseIDs,
                orderedExerciseIDs: operation.orderedExerciseIDs,
                exerciseID: operation.exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                loadAdjustmentIntent: operation.loadAdjustmentIntent,
                targetSets: operation.targetSets,
                warmupSets: operation.warmupSets,
                targetReps: operation.targetReps
            )
        case .reorder:
            let ordered = operation.orderedExerciseIDs?.map { id in
                resolve(
                    id,
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: excludedExerciseIDs,
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    phraseHint: nil,
                    mustBeInSession: true,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates,
                    recordUnresolved: false
                ) ?? id
            }
            return SessionAdjustmentOperation(
                kind: operation.kind,
                orderedExerciseIDs: ordered
            )
        case .adjustSets, .adjustWarmupSets, .adjustLoad, .adjustRPE:
            let exerciseID = resolve(
                operation.exerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: nil,
                mustBeInSession: true,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                exerciseID: exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                loadAdjustmentIntent: operation.loadAdjustmentIntent,
                targetSets: operation.targetSets,
                warmupSets: operation.warmupSets,
                targetReps: operation.targetReps
            )
        case .addExercise:
            let hints: [String?]
            if restrictAddHintsToSpan {
                hints = [addSpan]
            } else {
                hints = [addSpan ?? SessionSwapPhrase.parseAdd(phraseHint), phraseHint, replyHint]
            }
            let to = resolveCatalogTarget(
                modelID: operation.toExerciseID,
                hints: hints,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                toExerciseID: to,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                targetSets: operation.targetSets,
                warmupSets: operation.warmupSets,
                targetReps: operation.targetReps
            )
        }
    }

    /// "…and move it to the start" becomes a full permutation after simulating
    /// any swap in the same payload. PlanKit reorder drops unnamed session rows.
    private static func applyRelativeMove(
        operations: [SessionAdjustmentOperation],
        phraseHint: String?,
        orderedSessionExerciseIDs: [String],
        exerciseDisplayNames: [String: String]
    ) -> [SessionAdjustmentOperation] {
        guard let move = SessionSwapPhrase.parseMove(phraseHint),
              !orderedSessionExerciseIDs.isEmpty
        else { return operations }

        let swap = operations.first(where: { $0.kind == .swap })
        let added = operations.first(where: { $0.kind == .addExercise })
        let targetID: String?
        if let name = move.target {
            let needle = ExerciseSearchNormalizer.normalizeKeepingEquipment(name)
            if let to = swap?.toExerciseID ?? added?.toExerciseID {
                let toLabel = ExerciseDisplayFormatter.friendlyName(
                    for: to,
                    displayNames: exerciseDisplayNames
                )
                if ExerciseSearchNormalizer.normalizeKeepingEquipment(toLabel).contains(needle)
                    || to == name {
                    targetID = to
                } else {
                    targetID = matchSessionLabel(
                        needle,
                        order: orderedSessionExerciseIDs,
                        displayNames: exerciseDisplayNames
                    ) ?? to
                }
            } else {
                targetID = matchSessionLabel(
                    needle,
                    order: orderedSessionExerciseIDs,
                    displayNames: exerciseDisplayNames
                )
            }
        } else {
            targetID = swap?.toExerciseID ?? added?.toExerciseID
        }
        guard let targetID else { return operations }

        let ordered = SessionSwapPhrase.expandOrder(
            sessionOrder: orderedSessionExerciseIDs,
            replacing: swap?.fromExerciseID,
            with: swap?.toExerciseID ?? added?.toExerciseID,
            moving: targetID,
            to: move.position
        )
        guard Set(ordered).isSuperset(of: Set(orderedSessionExerciseIDs).subtracting([swap?.fromExerciseID].compactMap { $0 }))
        else { return operations }

        let reorder = SessionAdjustmentOperation(kind: .reorder, orderedExerciseIDs: ordered)
        var result = operations.filter { $0.kind != .reorder }
        result.append(reorder)
        return result
    }

    private static func matchSessionLabel(
        _ needle: String,
        order: [String],
        displayNames: [String: String]
    ) -> String? {
        let hits = order.filter { id in
            let label = ExerciseDisplayFormatter.friendlyName(for: id, displayNames: displayNames)
            let haystack = ExerciseSearchNormalizer.normalizeKeepingEquipment(label)
            return haystack.contains(needle) || id == needle
        }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Athlete "swap X for Y" FROM phrase beats a wrong model archetype
    /// (`chest_dip` vs live "Bench Dip").
    private static func resolveSessionSource(
        modelID: String?,
        athleteFrom: String?,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        unresolved: inout [String],
        catalogCandidates: inout [String]
    ) -> String? {
        if let athleteFrom, !SessionSwapPhrase.isPronoun(athleteFrom) {
            let context = ExerciseResolver.Context(
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                mustBeInSession: true,
                phraseHint: athleteFrom
            )
            if let exerciseID = ExerciseResolver.resolve(
                athleteFrom,
                context: context,
                persistence: persistence
            ).exerciseID {
                return exerciseID
            }
        }

        return resolve(
            modelID,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            phraseHint: athleteFrom,
            mustBeInSession: true,
            unresolved: &unresolved,
            catalogCandidates: &catalogCandidates
        )
    }

    private static func resolve(
        _ rawID: String?,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        phraseHint: String?,
        mustBeInSession: Bool,
        unresolved: inout [String],
        catalogCandidates: inout [String],
        recordUnresolved: Bool = true
    ) -> String? {
        guard let rawID, !rawID.isEmpty else { return rawID }

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            mustBeInSession: mustBeInSession,
            phraseHint: phraseHint
        )
        let resolved = ExerciseResolver.resolve(rawID, context: context, persistence: persistence)
        if let exerciseID = resolved.exerciseID {
            return exerciseID
        }

        if recordUnresolved {
            unresolved.append(rawID)
            catalogCandidates.append(contentsOf: resolved.catalogCandidates)
        }
        if mustBeInSession {
            return nil
        }
        return rawID
    }

    /// Athlete wording and coach reply win over a conflicting toExerciseID (e.g. Face Pull vs hammer curls).
    private static func resolveCatalogTarget(
        modelID: String?,
        hints: [String?],
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        unresolved: inout [String],
        catalogCandidates: inout [String]
    ) -> String? {
        for hint in hints {
            guard let hint, looksLikeExerciseHint(hint),
                  ExerciseResolver.isEquipmentOnlyPhrase(hint) == false
            else { continue }
            let context = ExerciseResolver.Context(
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                mustBeInSession: false,
                phraseHint: hint
            )
            let result = ExerciseResolver.resolve(hint, context: context, persistence: persistence)
            if let exerciseID = result.exerciseID {
                catalogCandidates.append(contentsOf: result.catalogCandidates)
                return exerciseID
            }
            catalogCandidates.append(contentsOf: result.catalogCandidates)
            let isShortSpan = hint.split(whereSeparator: { $0.isWhitespace }).count <= 8
            if isShortSpan {
                // Athlete named a lift; do not fall through to a conflicting model ID.
                if let modelID, !modelID.isEmpty {
                    unresolved.append(modelID)
                }
                return nil
            }
        }

        return resolve(
            modelID,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            phraseHint: hints.compactMap { $0 }.first,
            mustBeInSession: false,
            unresolved: &unresolved,
            catalogCandidates: &catalogCandidates
        )
    }

    private static func looksLikeExerciseHint(_ text: String) -> Bool {
        let lower = text.lowercased()
        let liftNeedles = [
            "curl", "press", "row", "pull", "squat", "deadlift", "fly", "raise",
            "extension", "dip", "lunge", "pulldown", "crunch", "plank", "hinge",
            "thrust", "shrug", "kickback", "pushdown", "hammer"
        ]
        if liftNeedles.contains(where: { lower.contains($0) }) {
            return true
        }
        return CoachArchetypeSupport.archetypeID(for: text) != nil
    }
}
