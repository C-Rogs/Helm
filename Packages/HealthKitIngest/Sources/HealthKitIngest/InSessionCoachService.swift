import CoachLLM
import Core
import Diagnostics
import Foundation
import Persistence
import PlanKit

public struct AppliedSessionAdjustment: Sendable, Equatable {
    public let banner: SessionAdjustmentBannerModel
    public let previousExercises: [WorkoutSessionExerciseDraft]
    public let swappedExerciseIDs: [String]

    public init(
        banner: SessionAdjustmentBannerModel,
        previousExercises: [WorkoutSessionExerciseDraft],
        swappedExerciseIDs: [String]
    ) {
        self.banner = banner
        self.previousExercises = previousExercises
        self.swappedExerciseIDs = swappedExerciseIDs
    }
}

public enum CoachProposalFailure: Sendable, Equatable {
    case clamp(PrescriptionClampReason)
    case exerciseNotFound(String)
    case noDiff
    case unresolvedExerciseIDs(ids: [String], sessionLabels: [String])
    case unresolvedCatalogExerciseIDs(ids: [String], catalogLabels: [String])

    public var userMessage: String {
        switch self {
        case .clamp(let reason):
            return clampMessage(reason)
        case .exerciseNotFound(let id):
            let label = ExerciseDisplayFormatter.humanizeID(id)
            return "Couldn't apply that change: \(label) isn't in this session. Ask again using the exercise name from your plan."
        case .noDiff:
            return "Couldn't apply that change: your plan is already at that target (or that equipment variant is already selected)."
        case .unresolvedExerciseIDs(let ids, let sessionLabels):
            let unmatched = ids.map { "\"\($0)\"" }.joined(separator: ", ")
            let available = sessionLabels.joined(separator: ", ")
            return "Couldn't apply that change: \(unmatched) doesn't match any exercise in this session. Available exercises: \(available)."
        case .unresolvedCatalogExerciseIDs(let ids, let catalogLabels):
            let unmatched = ids.map { "\"\($0)\"" }.joined(separator: ", ")
            if catalogLabels.isEmpty {
                return "Couldn't find \(unmatched) in the exercise catalogue. Try a more specific name (equipment + movement)."
            }
            let options = catalogLabels.joined(separator: ", ")
            return "Couldn't lock \(unmatched) to one catalogue exercise. Closest matches: \(options). Tell me which one to add."
        }
    }

    private func clampMessage(_ reason: PrescriptionClampReason) -> String {
        switch reason {
        case .loadMissing:
            return "Couldn't apply that change: that exercise has no target weight yet. Tell me the exact weight you want."
        case .rpeMissing:
            return "Couldn't apply that change: I didn't catch a target RPE. Tell me the number you want."
        case .swapTargetExcluded, .swapNoAlternativeAvailable:
            return "Couldn't apply that change: no suitable swap is available."
        case .invalidReorder:
            return "Couldn't apply that change: exercise order didn't match this session."
        case .exerciseNotFound:
            return "Couldn't apply that change: exercise not found in the catalogue."
        case .duplicateExercise(let exerciseID):
            let label = ExerciseDisplayFormatter.humanizeID(exerciseID)
            return "Couldn't add \(label): it's already in this session."
        }
    }
}

public enum CoachProposalStatus: Sendable, Equatable {
    case advisory
    case confirmable
    case failed(CoachProposalFailure)
}

public struct CoachSessionProposal: Sendable, Equatable {
    public let reply: String
    public let payload: SessionAdjustmentPayload
    public let recommendationID: String
    public let previewBanner: SessionAdjustmentBannerModel?
    public let status: CoachProposalStatus
    public let requestID: UUID?
    /// Original athlete turn, used to re-normalize equipment phrases on confirm.
    public let sourceUserMessage: String?

    public var requiresConfirmation: Bool {
        if case .confirmable = status { return true }
        return false
    }

    public var failureNotice: String? {
        guard case .failed(let failure) = status else { return nil }
        return failure.userMessage
    }

    /// Failed turns must not keep an optimistic "Swapped..." reply as the athlete-facing line.
    public var displayedAssistantText: String {
        if case .confirmable = status {
            if let previewBanner {
                return "Tap to confirm: \(previewBanner.fromLabel) → \(previewBanner.toLabel)."
            }
            return "Tap to confirm this session change."
        }
        return failureNotice ?? reply
    }

    /// Questions and complaints keep the spoken answer. The same failure line is not repeated.
    public func athleteFacingText(previousAssistant: String?) -> String {
        let previous = previousAssistant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let canned = failureNotice
        if let canned, previous == canned {
            return "I didn't change the session. Name the exercise and what you want different."
        }
        let asked = sourceUserMessage ?? ""
        if CoachChatIntent.prefersSpokenAnswer(asked) || CoachChatIntent.refusesWorkoutStart(asked) {
            let spoken = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty, spoken != canned {
                return spoken
            }
        }
        return displayedAssistantText
    }

    /// Confirm cards stay off when this turn was a question, a complaint, or a refusal to start.
    public var shouldOfferConfirmation: Bool {
        guard requiresConfirmation else { return false }
        let asked = sourceUserMessage ?? ""
        if CoachChatIntent.prefersSpokenAnswer(asked) || CoachChatIntent.refusesWorkoutStart(asked) {
            return false
        }
        return true
    }

    public init(
        reply: String,
        payload: SessionAdjustmentPayload,
        recommendationID: String,
        previewBanner: SessionAdjustmentBannerModel?,
        status: CoachProposalStatus,
        requestID: UUID? = nil,
        sourceUserMessage: String? = nil
    ) {
        self.reply = reply
        self.payload = payload
        self.recommendationID = recommendationID
        self.previewBanner = previewBanner
        self.status = status
        self.requestID = requestID
        self.sourceUserMessage = sourceUserMessage
    }
}

public enum InSessionCoachError: Error, Sendable, Equatable {
    case noActiveSession
    case adjustmentRejected(PrescriptionClampReason)
    case providerUnavailable(String)
    case noApplicableChange
}

public struct InSessionCoachService: Sendable {
    private let persistence: PersistenceStore

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    public func proposeAdjustment(
        userMessage: String,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        context: CoachContextDays,
        thread: CoachThreadState = .empty,
        liveVitals: InSessionLiveVitals? = nil
    ) async throws -> CoachSessionProposal {
        let signpost = HelmSignpost(name: .inSessionCoachPropose, category: .coachLLM)
        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        defer { signpost.end(id: signpostID) }

        let availability = await provider.availability()
        guard availability.isAvailable else {
            let message: String
            if case .unavailable(_, let helpText) = availability {
                message = helpText ?? "Coach unavailable"
            } else {
                message = "Coach unavailable"
            }
            throw InSessionCoachError.providerUnavailable(message)
        }

        let prompt = buildPrompt(
            snapshot: snapshot,
            profile: profile,
            context: context,
            excludedExerciseIDs: excludedExerciseIDs,
            liveVitals: liveVitals
        )

        let artefact = try await provider.generateSessionAdjustment(
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: userMessage,
            thread: thread
        )

        let proposal = try buildProposal(
            payload: artefact.payload,
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            modelVersion: artefact.schemaVersion.rawValue,
            requestID: artefact.requestID
        )

        if let retried = try await retryUnresolvedProposal(
            initial: proposal,
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            provider: provider,
            prompt: prompt,
            thread: thread
        ) {
            await logProposalDiagnostics(proposal: retried, sessionID: snapshot.session.id)
            return retried
        }
        await logProposalDiagnostics(proposal: proposal, sessionID: snapshot.session.id)
        return proposal
    }

    private func retryUnresolvedProposal(
        initial: CoachSessionProposal,
        userMessage: String,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        prompt: CoachPrompt,
        thread: CoachThreadState
    ) async throws -> CoachSessionProposal? {
        let retryMessage: String?
        switch initial.status {
        case .failed(.unresolvedCatalogExerciseIDs(let ids, let candidates)) where !candidates.isEmpty:
            helmLogger(category: .coachLLM).info(
                "coach lookup retry: \(ids.joined(separator: ", "), privacy: .public) -> \(candidates.count) candidates"
            )
            retryMessage = """
            Your previous reply referenced exercise\(ids.count == 1 ? "" : "s") \(ids.map { "\"\($0)\"" }.joined(separator: ", ")) \
            that could not be matched to exactly one catalogue exercise. Closest catalogue matches: \
            \(candidates.joined(separator: "; ")). Re-issue the operations using the exact catalogue display name \
            for the exercise the athlete means, or omit the operation if none of the matches is right. \
            Athlete request was: \(userMessage)
            """
        case .failed(.unresolvedExerciseIDs(let ids, let sessionLabels)) where !sessionLabels.isEmpty:
            helmLogger(category: .coachLLM).info(
                "coach session retry: \(ids.joined(separator: ", "), privacy: .public) -> \(sessionLabels.count) session labels"
            )
            retryMessage = """
            Your previous reply referenced exercise\(ids.count == 1 ? "" : "s") \(ids.map { "\"\($0)\"" }.joined(separator: ", ")) \
            that could not be matched to this session. Use one of these exact session exercise names: \
            \(sessionLabels.joined(separator: "; ")). Re-issue the operations or omit them if none fit. \
            Athlete request was: \(userMessage)
            """
        default:
            retryMessage = nil
        }

        guard let retryUserMessage = retryMessage else { return nil }

        let retryArtefact = try await provider.generateSessionAdjustment(
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: retryUserMessage,
            thread: thread
        )
        let retryProposal = try buildProposal(
            payload: retryArtefact.payload,
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            modelVersion: retryArtefact.schemaVersion.rawValue,
            requestID: retryArtefact.requestID
        )

        switch retryProposal.status {
        case .failed(.unresolvedCatalogExerciseIDs), .failed(.unresolvedExerciseIDs):
            return nil
        default:
            return retryProposal
        }
    }

    public func applyProposal(
        _ proposal: CoachSessionProposal,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>
    ) async throws -> HelmActionResult {
        guard proposal.requiresConfirmation else {
            throw InSessionCoachError.noApplicableChange
        }

        let result = try await HelmActionExecutor(persistence: persistence).run(
            .applySessionAdjustment(HelmSessionAdjustmentCommand(
                payload: proposal.payload,
                snapshot: snapshot,
                excludedExerciseIDs: excludedExerciseIDs,
                userMessage: proposal.sourceUserMessage,
                modelVersion: proposal.payload.schemaVersion,
                recommendationID: proposal.recommendationID,
                markActedOn: true
            ))
        )

        try persistence.coachRecommendations.markActedOn(id: proposal.recommendationID)
        return result
    }

    public func dismissProposal(recommendationID: String) throws {
        try persistence.coachRecommendations.markDismissed(id: recommendationID)
    }

    @available(*, deprecated, message: "Use proposeAdjustment and applyProposal instead.")
    public func askCoachInSession(
        userMessage: String,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        context: [CoachContextDay]
    ) async throws -> AppliedSessionAdjustment {
        let proposal = try await proposeAdjustment(
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            provider: provider,
            profile: profile,
            context: CoachContextDays(recent: context),
            thread: .empty
        )
        guard proposal.requiresConfirmation else {
            throw InSessionCoachError.noApplicableChange
        }
        let result = try await applyProposal(
            proposal,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs
        )
        guard let applied = result.sessionAdjustment else {
            throw InSessionCoachError.noApplicableChange
        }
        return applied
    }

    public func applyAdjustment(
        payload: SessionAdjustmentPayload,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        userMessage: String? = nil,
        modelVersion: String? = CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
        recommendationID: String? = nil,
        markActedOn: Bool = true
    ) throws -> AppliedSessionAdjustment {
        let stampedPayload = LoadAdjustmentIntentClassifier.stamp(
            payload: payload,
            userMessage: userMessage
        )
        let sessionExerciseIDs = Set(snapshot.session.exercises.map(\.exerciseID))
        let orderedSessionExerciseIDs = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .map(\.exerciseID)
        let displayNames = try persistence.exercises.displayNames(for: Array(sessionExerciseIDs))
        let (catalog, familiarExerciseIDs, recentExerciseIDs) = try loadCatalog()
        let normalized = try SessionExerciseIDResolver.normalize(
            payload: stampedPayload,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: displayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            phraseHint: userMessage,
            orderedSessionExerciseIDs: orderedSessionExerciseIDs
        )

        guard normalized.unresolvedExerciseIDs.isEmpty else {
            throw InSessionCoachError.noApplicableChange
        }

        let seededPayload = try seedAddExerciseLoads(
            payload: normalized.payload,
            userMessage: userMessage,
            catalog: catalog
        )
        let currentPrescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: seededPayload)

        guard !adjustment.operations.isEmpty else {
            throw InSessionCoachError.noApplicableChange
        }

        let result = PlanKit.apply(
            adjustment: adjustment,
            to: currentPrescription,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            familiarExerciseIDs: familiarExerciseIDs
        )

        switch result {
        case .rejected(let reason):
            throw InSessionCoachError.adjustmentRejected(reason)
        case .applied(let adjusted):
            guard PrescriptionDiff.exercisesChanged(from: currentPrescription, to: adjusted) else {
                throw InSessionCoachError.noApplicableChange
            }

            let bannerLabels = try makeBanner(
                payload: seededPayload,
                previous: currentPrescription,
                adjusted: adjusted
            )

            let previousExercises = snapshot.session.exercises
            try persistence.activeSessions.syncFromPrescription(
                sessionID: snapshot.session.id,
                prescription: adjusted,
                timestamp: Date()
            )

            let resolvedRecommendationID: String
            if let recommendationID {
                resolvedRecommendationID = recommendationID
            } else {
                let stored = try logRecommendation(
                    sessionID: snapshot.session.id,
                    payload: seededPayload,
                    modelVersion: modelVersion,
                    markActedOn: markActedOn
                )
                resolvedRecommendationID = stored.id
            }

            return AppliedSessionAdjustment(
                banner: SessionAdjustmentBannerModel(
                    fromLabel: bannerLabels.fromLabel,
                    toLabel: bannerLabels.toLabel,
                    reason: seededPayload.bannerReason,
                    recommendationID: resolvedRecommendationID
                ),
                previousExercises: previousExercises,
                swappedExerciseIDs: swappedExerciseIDs(
                    payload: seededPayload,
                    previous: currentPrescription,
                    adjusted: adjusted
                )
            )
        }
    }

    /// CAM-96: coach addExercise must not invent working loads. Prefer athlete-named kg,
    /// otherwise ProgressionEngine (same path as planned-session prescription).
    private func seedAddExerciseLoads(
        payload: SessionAdjustmentPayload,
        userMessage: String?,
        catalog: [CatalogExercise]
    ) throws -> SessionAdjustmentPayload {
        guard payload.operations.contains(where: { $0.kind == .addExercise }) else {
            return payload
        }

        let athleteNamedKg = SessionSwapPhrase.parseNamedLoadKg(userMessage)
        let athleteNamedWeight = athleteNamedKg != nil
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)
        let history = try PrescriptionHistoryBuilder.history(from: persistence, endingAt: day)
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0) })

        let operations = payload.operations.map { operation -> SessionAdjustmentOperation in
            guard operation.kind == .addExercise, let exerciseID = operation.toExerciseID else {
                return operation
            }

            if athleteNamedWeight {
                let massKg = athleteNamedKg ?? operation.targetMassKg
                return SessionAdjustmentOperation(
                    kind: operation.kind,
                    fromExerciseID: operation.fromExerciseID,
                    toExerciseID: operation.toExerciseID,
                    excludeExerciseIDs: operation.excludeExerciseIDs,
                    orderedExerciseIDs: operation.orderedExerciseIDs,
                    exerciseID: operation.exerciseID,
                    setDelta: operation.setDelta,
                    massDeltaKg: operation.massDeltaKg,
                    targetMassKg: massKg,
                    rpeDelta: operation.rpeDelta,
                    targetRPE: operation.targetRPE,
                    loadAdjustmentIntent: operation.loadAdjustmentIntent,
                    targetSets: operation.targetSets,
                    warmupSets: operation.warmupSets,
                    targetReps: operation.targetReps
                )
            }

            // Live coach turns: replace invented LLM kg with engine. Direct applies
            // (nil userMessage, e.g. tests) keep an explicit targetMassKg when present.
            if userMessage == nil, operation.targetMassKg != nil {
                return operation
            }

            let progression = PlanKit.progression(
                for: exerciseID,
                history: history.loggedSets,
                muscleMap: catalogByID[exerciseID]?.muscleMap
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                fromExerciseID: operation.fromExerciseID,
                toExerciseID: operation.toExerciseID,
                excludeExerciseIDs: operation.excludeExerciseIDs,
                orderedExerciseIDs: operation.orderedExerciseIDs,
                exerciseID: operation.exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: progression.workingWeight?.kilograms,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                loadAdjustmentIntent: operation.loadAdjustmentIntent,
                targetSets: operation.targetSets,
                warmupSets: operation.warmupSets,
                targetReps: operation.targetReps ?? progression.targetRepMin
            )
        }

        return SessionAdjustmentPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            rationale: payload.rationale,
            operations: operations
        )
    }

    func buildProposal(
        payload: SessionAdjustmentPayload,
        userMessage: String? = nil,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        modelVersion: String?,
        requestID: UUID? = nil
    ) throws -> CoachSessionProposal {
        let stampedPayload = LoadAdjustmentIntentClassifier.stamp(
            payload: payload,
            userMessage: userMessage
        )
        let sessionExerciseIDs = Set(snapshot.session.exercises.map(\.exerciseID))
        let orderedSessionExerciseIDs = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .map(\.exerciseID)
        let displayNames = try persistence.exercises.displayNames(for: Array(sessionExerciseIDs))
        let (catalog, familiarExerciseIDs, recentExerciseIDs) = try loadCatalog()
        let normalized = try SessionExerciseIDResolver.normalize(
            payload: stampedPayload,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: displayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            phraseHint: userMessage,
            orderedSessionExerciseIDs: orderedSessionExerciseIDs
        )

        let storedPayload = normalized.unresolvedExerciseIDs.isEmpty ? normalized.payload : stampedPayload
        let recommendation = try logRecommendation(
            sessionID: snapshot.session.id,
            payload: storedPayload,
            modelVersion: modelVersion,
            markActedOn: false
        )

        if payload.operations.isEmpty {
            return CoachSessionProposal(
                reply: payload.reply,
                payload: payload,
                recommendationID: recommendation.id,
                previewBanner: nil,
                status: .advisory,
                requestID: requestID,
                sourceUserMessage: userMessage
            )
        }

        if !normalized.unresolvedExerciseIDs.isEmpty {
            let sessionUnresolved = Set(normalized.unresolvedExerciseIDs)
                .subtracting(normalized.unresolvedCatalogIDs)
            if sessionUnresolved.isEmpty {
                return CoachSessionProposal(
                    reply: payload.reply,
                    payload: normalized.payload,
                    recommendationID: recommendation.id,
                    previewBanner: nil,
                    status: .failed(.unresolvedCatalogExerciseIDs(
                        ids: normalized.unresolvedCatalogIDs,
                        catalogLabels: normalized.catalogCandidates
                    )),
                    requestID: requestID,
                    sourceUserMessage: userMessage
                )
            }

            let sessionLabels = snapshot.session.exercises
                .sorted { $0.displayOrder < $1.displayOrder }
                .map { exercise in
                    ExerciseDisplayFormatter.friendlyName(
                        for: exercise.exerciseID,
                        displayNames: displayNames
                    )
                }
            return CoachSessionProposal(
                reply: payload.reply,
                payload: normalized.payload,
                recommendationID: recommendation.id,
                previewBanner: nil,
                status: .failed(.unresolvedExerciseIDs(
                    ids: normalized.unresolvedExerciseIDs,
                    sessionLabels: sessionLabels
                )),
                requestID: requestID,
                sourceUserMessage: userMessage
            )
        }

        let seededPayload = try seedAddExerciseLoads(
            payload: normalized.payload,
            userMessage: userMessage,
            catalog: catalog
        )
        let currentPrescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: seededPayload)

        let result = PlanKit.apply(
            adjustment: adjustment,
            to: currentPrescription,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            familiarExerciseIDs: familiarExerciseIDs
        )

        switch result {
        case .rejected(let reason):
            return CoachSessionProposal(
                reply: payload.reply,
                payload: seededPayload,
                recommendationID: recommendation.id,
                previewBanner: nil,
                status: .failed(.clamp(reason)),
                requestID: requestID,
                sourceUserMessage: userMessage
            )
        case .applied(let adjusted):
            guard PrescriptionDiff.exercisesChanged(from: currentPrescription, to: adjusted) else {
                return CoachSessionProposal(
                    reply: payload.reply,
                    payload: seededPayload,
                    recommendationID: recommendation.id,
                    previewBanner: nil,
                    status: .failed(.noDiff),
                    requestID: requestID,
                    sourceUserMessage: userMessage
                )
            }

            let bannerLabels = try makeBanner(
                payload: seededPayload,
                previous: currentPrescription,
                adjusted: adjusted
            )

            return CoachSessionProposal(
                reply: payload.reply,
                payload: seededPayload,
                recommendationID: recommendation.id,
                previewBanner: SessionAdjustmentBannerModel(
                    fromLabel: bannerLabels.fromLabel,
                    toLabel: bannerLabels.toLabel,
                    reason: seededPayload.bannerReason,
                    recommendationID: recommendation.id
                ),
                status: .confirmable,
                requestID: requestID,
                sourceUserMessage: userMessage
            )
        }
    }

    private func buildPrompt(
        snapshot: ActiveSessionSnapshot,
        profile: MemoryProfile,
        context: CoachContextDays,
        excludedExerciseIDs: Set<String>,
        liveVitals: InSessionLiveVitals? = nil
    ) -> CoachPrompt {
        var contextBlock = ContextBuilder.build(
            profile: profile,
            days: context,
            budget: TokenBudget.maxInputTokens(for: .gemini),
            turn: .followUp
        ).contextBlock

        let exerciseIDs = snapshot.session.exercises.map(\.exerciseID)
        let displayNames = (try? persistence.exercises.displayNames(for: exerciseIDs)) ?? [:]

        let sortedExercises = snapshot.session.exercises.sorted { $0.displayOrder < $1.displayOrder }
        let exerciseBlock = InSessionCoachContextBuilder.sessionExerciseBlock(
            snapshot: snapshot,
            displayNames: displayNames,
            importContextNotes: InSessionCoachContextBuilder.importContextNotes(from: snapshot.session.notes)
        )

        let sessionArchetypeIDs = Set(
            CoachArchetypeSupport.sessionArchetypeIDs(
                for: sortedExercises.map(\.exerciseID)
            )
        )
        let archetypeLines = CoachArchetypeSupport.catalog.archetypes
            .filter { sessionArchetypeIDs.contains($0.id) || $0.priority == "core" || $0.priority == "common" }
            .sorted { lhs, rhs in
                let lhsInSession = sessionArchetypeIDs.contains(lhs.id)
                let rhsInSession = sessionArchetypeIDs.contains(rhs.id)
                if lhsInSession != rhsInSession { return lhsInSession }
                return lhs.displayName < rhs.displayName
            }
            .map { "- \($0.id) | \($0.displayName)" }
            .joined(separator: "\n")

        if let liveVitals {
            let vitals = InSessionCoachContextBuilder.liveVitalsBlock(liveVitals)
            contextBlock = contextBlock.isEmpty ? vitals : contextBlock + "\n\n" + vitals
        }

        let meta = InSessionCoachContextBuilder.sessionMetaBlock(snapshot: snapshot)
        contextBlock = contextBlock.isEmpty ? meta : contextBlock + "\n\n" + meta

        if let notes = snapshot.session.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty,
           snapshot.session.source != .importSource {
            contextBlock += "\n\nAthlete session note:\n\(notes)"
        }
        if !archetypeLines.isEmpty {
            contextBlock += "\n\nAllowed archetype IDs (use exact archetypeId in operations):\n\(archetypeLines)"
        }
        if !exerciseBlock.isEmpty {
            contextBlock += "\n\nActive session exercises:\n\(exerciseBlock)"
        }
        if let loadRationale = try? sessionLoadRationaleBlock(
            exerciseIDs: sortedExercises.map(\.exerciseID),
            displayNames: displayNames
        ), !loadRationale.isEmpty {
            contextBlock += "\n\n# Prescription Load Rationale\n\(loadRationale)"
        }
        if let picker = try? persistence.exercises.listForPicker(search: nil, limit: 120),
           !picker.isEmpty {
            let available = InSessionCoachContextBuilder.availableExercisesBlock(picker)
            if !available.isEmpty {
                contextBlock += "\n\n\(available)"
            }
        }
        if !excludedExerciseIDs.isEmpty {
            let excludedArchetypes = excludedExerciseIDs.compactMap { CoachArchetypeSupport.archetype(for: $0)?.id }
            contextBlock += "\n\nExcluded archetype IDs (already swapped this session):\n"
                + excludedArchetypes.sorted().joined(separator: ", ")
        }

        return CoachPrompt(
            systemInstructions: CoachSystemPrompt.sessionAdjustmentV2,
            contextBlock: contextBlock,
            estimatedTokens: TokenBudget.estimateTokens(characterCount: contextBlock.count),
            includedDayCount: context.recent.count,
            droppedDayCount: 0
        )
    }

    private func sessionLoadRationaleBlock(
        exerciseIDs: [String],
        displayNames: [String: String]
    ) throws -> String {
        guard !exerciseIDs.isEmpty else { return "" }
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)
        let history = try PrescriptionHistoryBuilder.history(from: persistence, endingAt: day)
        let (catalog, _, _) = try loadCatalog()
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0) })
        let inputs = exerciseIDs.map { exerciseID in
            PrescriptionLoadRationale.ExerciseInput(
                exerciseID: exerciseID,
                displayName: ExerciseDisplayFormatter.friendlyName(
                    for: exerciseID,
                    displayNames: displayNames
                ),
                progression: PlanKit.progression(
                    for: exerciseID,
                    history: history.loggedSets,
                    muscleMap: catalogByID[exerciseID]?.muscleMap
                ),
                constraintAffected: false
            )
        }
        return PrescriptionLoadRationale.format(exercises: inputs)
    }

    private func loadCatalog() throws -> (
        catalog: [CatalogExercise],
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>
    ) {
        let rows = try persistence.exercises.fetchCatalogRows()
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day
        )
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let recentExerciseIDs = Set((try? persistence.exercises.listRecentlyUsed())?.map(\.id) ?? [])
        let catalog = PrescriptionCatalogBuilder.build(
            from: rows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        return (catalog, familiarExerciseIDs, recentExerciseIDs)
    }

    private func logRecommendation(
        sessionID: String,
        payload: SessionAdjustmentPayload,
        modelVersion: String?,
        markActedOn: Bool
    ) throws -> StoredCoachRecommendation {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let json = String(decoding: data, as: UTF8.self)

        // Pre-start Discuss uses a synthetic snapshot id; there is no workout_session row yet.
        let workoutSessionID = sessionID == PrescriptionCoachSnapshotBuilder.preStartSessionID
            ? nil
            : sessionID

        let stored = try persistence.coachRecommendations.insert(
            CoachRecommendationInsert(
                scope: .session,
                workoutSessionID: workoutSessionID,
                recommendationType: .sessionAdjustment,
                payloadJSON: json,
                modelVersion: modelVersion
            )
        )
        if markActedOn {
            try persistence.coachRecommendations.markActedOn(id: stored.id)
        }
        return stored
    }

    private func makeBanner(
        payload: SessionAdjustmentPayload,
        previous: SessionPrescription,
        adjusted: SessionPrescription
    ) throws -> (fromLabel: String, toLabel: String) {
        let ids = Array(Set(previous.exercises.map(\.exerciseID) + adjusted.exercises.map(\.exerciseID)))
        let names = try persistence.exercises.displayNames(for: ids)

        guard let operation = payload.operations.first else {
            throw InSessionCoachError.noApplicableChange
        }

        switch operation.kind {
        case .swap:
            let fromID = operation.fromExerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let toID = operation.toExerciseID
                ?? adjusted.exercises.first(where: { $0.exerciseID != fromID })?.exerciseID
                ?? adjusted.exercises.first?.exerciseID
                ?? fromID
            var toName = ExerciseDisplayFormatter.friendlyName(for: toID, displayNames: names)
            if let ordered = payload.operations.first(where: { $0.kind == .reorder })?.orderedExerciseIDs {
                if ordered.first == toID {
                    toName += " (first)"
                } else if ordered.last == toID {
                    toName += " (last)"
                }
            }
            return (
                ExerciseDisplayFormatter.friendlyName(for: fromID, displayNames: names),
                toName
            )
        case .reorder:
            return ("Exercise order", "Updated")
        case .adjustSets:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let delta = operation.setDelta ?? 0
            let sign = delta > 0 ? "+\(delta)" : "\(delta)"
            return (
                ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names),
                "\(sign) sets"
            )
        case .adjustWarmupSets:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let previousWarmups = previous.exercises.first { $0.exerciseID == exerciseID }?.warmupSets ?? 0
            let nextWarmups = adjusted.exercises.first { $0.exerciseID == exerciseID }?.warmupSets ?? previousWarmups
            let delta = nextWarmups - previousWarmups
            let sign = delta > 0 ? "+\(delta)" : "\(delta)"
            return (
                ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names),
                "\(sign) warm-up"
            )
        case .adjustLoad:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let toExercise = adjusted.exercises.first { $0.exerciseID == exerciseID }
            let fromExercise = previous.exercises.first { $0.exerciseID == exerciseID }
            let fromLabel = ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names)
            var parts: [String] = []
            if let toMass = toExercise?.targetMass?.kilograms {
                parts.append(formatMass(toMass))
            }
            let toReps = toExercise?.targetRepMin ?? toExercise?.targetRepMax
            let fromReps = fromExercise?.targetRepMin ?? fromExercise?.targetRepMax
            if let toReps, toReps != fromReps || parts.isEmpty {
                parts.append("x \(toReps)")
            }
            guard !parts.isEmpty else {
                throw InSessionCoachError.noApplicableChange
            }
            return (fromLabel, parts.joined(separator: " "))
        case .adjustRPE:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let toExercise = adjusted.exercises.first { $0.exerciseID == exerciseID }
            let fromLabel = ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names)
            guard let toRPE = toExercise?.targetRPE else {
                throw InSessionCoachError.noApplicableChange
            }
            return (fromLabel, formatRPE(toRPE))
        case .addExercise:
            let toID = operation.toExerciseID ?? adjusted.exercises.last?.exerciseID ?? "Exercise"
            return (
                "Session",
                ExerciseDisplayFormatter.friendlyName(for: toID, displayNames: names)
            )
        }
    }

    private func formatMass(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f kg", kilograms)
            : String(format: "%.1f kg", kilograms)
    }

    private func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "RPE %.0f", value)
            : String(format: "RPE %.1f", value)
    }

    private func swappedExerciseIDs(
        payload: SessionAdjustmentPayload,
        previous: SessionPrescription,
        adjusted: SessionPrescription
    ) -> [String] {
        var ids: [String] = []
        for operation in payload.operations where operation.kind == .swap {
            if let from = operation.fromExerciseID {
                ids.append(from)
            }
            if let to = operation.toExerciseID {
                ids.append(to)
            } else if let from = operation.fromExerciseID,
                      let index = previous.exercises.firstIndex(where: { $0.exerciseID == from }),
                      adjusted.exercises.indices.contains(index) {
                ids.append(adjusted.exercises[index].exerciseID)
            }
        }
        return ids
    }

    private func logProposalDiagnostics(proposal: CoachSessionProposal, sessionID: String) async {
        let statusLabel: String
        let rejectReason: String?
        switch proposal.status {
        case .advisory:
            statusLabel = "advisory"
            rejectReason = nil
        case .confirmable:
            statusLabel = "confirmable"
            rejectReason = nil
        case .failed(let failure):
            statusLabel = "failed"
            rejectReason = String(describing: failure)
        }

        await InSessionCoachDiagnostics.recordPropose(
            sessionID: sessionID,
            requestID: proposal.requestID,
            opCount: proposal.payload.operations.count,
            status: statusLabel,
            rejectReason: rejectReason,
            schemaVersion: proposal.payload.schemaVersion
        )
    }
}
