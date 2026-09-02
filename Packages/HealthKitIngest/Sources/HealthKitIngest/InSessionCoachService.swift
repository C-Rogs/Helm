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
        failureNotice ?? reply
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

        // Ambiguous catalog lookup (e.g. "hip thrust"): one inference retry where
        // the model sees its failed phrase plus the resolver's closest matches and
        // must either commit to an exact catalogue display name or drop the op.
        guard case .failed(.unresolvedCatalogExerciseIDs(let ids, let candidates)) = proposal.status,
              !candidates.isEmpty else {
            await logProposalDiagnostics(proposal: proposal, sessionID: snapshot.session.id)
            return proposal
        }

        helmLogger(category: .coachLLM).info(
            "coach lookup retry: \(ids.joined(separator: ", "), privacy: .public) -> \(candidates.count) candidates"
        )

        let retryUserMessage = """
        Your previous reply referenced exercise\(ids.count == 1 ? "" : "s") \(ids.map { "\"\($0)\"" }.joined(separator: ", ")) \
        that could not be matched to exactly one catalogue exercise. Closest catalogue matches: \
        \(candidates.joined(separator: "; ")). Re-issue the operations using the exact catalogue display name \
        for the exercise the athlete means, or omit the operation if none of the matches is right. \
        Athlete request was: \(userMessage)
        """
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
        // Keep whichever attempt got further; the retry wins only if it resolved cleanly.
        if case .failed(.unresolvedCatalogExerciseIDs) = retryProposal.status {
            await logProposalDiagnostics(proposal: proposal, sessionID: snapshot.session.id)
            return proposal
        }
        await logProposalDiagnostics(proposal: retryProposal, sessionID: snapshot.session.id)
        return retryProposal
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

        let currentPrescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: normalized.payload)

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
                payload: normalized.payload,
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
                    payload: normalized.payload,
                    modelVersion: modelVersion,
                    markActedOn: markActedOn
                )
                resolvedRecommendationID = stored.id
            }

            return AppliedSessionAdjustment(
                banner: SessionAdjustmentBannerModel(
                    fromLabel: bannerLabels.fromLabel,
                    toLabel: bannerLabels.toLabel,
                    reason: normalized.payload.bannerReason,
                    recommendationID: resolvedRecommendationID
                ),
                previousExercises: previousExercises,
                swappedExerciseIDs: swappedExerciseIDs(
                    payload: normalized.payload,
                    previous: currentPrescription,
                    adjusted: adjusted
                )
            )
        }
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

        let currentPrescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: normalized.payload)

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
                payload: normalized.payload,
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
                    payload: normalized.payload,
                    recommendationID: recommendation.id,
                    previewBanner: nil,
                    status: .failed(.noDiff),
                    requestID: requestID,
                    sourceUserMessage: userMessage
                )
            }

            let bannerLabels = try makeBanner(
                payload: normalized.payload,
                previous: currentPrescription,
                adjusted: adjusted
            )

            return CoachSessionProposal(
                reply: payload.reply,
                payload: normalized.payload,
                recommendationID: recommendation.id,
                previewBanner: SessionAdjustmentBannerModel(
                    fromLabel: bannerLabels.fromLabel,
                    toLabel: bannerLabels.toLabel,
                    reason: normalized.payload.bannerReason,
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
