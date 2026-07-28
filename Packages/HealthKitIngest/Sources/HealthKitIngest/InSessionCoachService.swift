import CoachLLM
import Core
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

    public var userMessage: String {
        switch self {
        case .clamp(let reason):
            return clampMessage(reason)
        case .exerciseNotFound(let id):
            let label = ExerciseDisplayFormatter.humanizeID(id)
            return "Couldn't apply that change: \(label) isn't in this session. Ask again using the exercise name from your plan."
        case .noDiff:
            return "Couldn't apply that change: your plan is already at that target."
        case .unresolvedExerciseIDs(let ids, let sessionLabels):
            let unmatched = ids.map { "\"\($0)\"" }.joined(separator: ", ")
            let available = sessionLabels.joined(separator: ", ")
            return "Couldn't apply that change: \(unmatched) doesn't match any exercise in this session. Available exercises: \(available)."
        }
    }

    private func clampMessage(_ reason: PrescriptionClampReason) -> String {
        switch reason {
        case .setsBelowMinimum, .setsAboveMaximum:
            return "Couldn't apply that change: set count is outside safe bounds."
        case .loadMissing, .loadOutOfBounds:
            return "Couldn't apply that change: coach-suggested load increase is outside safe bounds. Tell me the exact weight you want."
        case .rpeOutOfBounds:
            return "Couldn't apply that change: RPE is outside safe bounds."
        case .swapTargetExcluded, .swapNoAlternativeAvailable:
            return "Couldn't apply that change: no suitable swap is available."
        case .invalidReorder:
            return "Couldn't apply that change: exercise order didn't match this session."
        case .exerciseNotFound:
            return "Couldn't apply that change: exercise not found in this session."
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

    public var requiresConfirmation: Bool {
        if case .confirmable = status { return true }
        return false
    }

    public var failureNotice: String? {
        guard case .failed(let failure) = status else { return nil }
        return failure.userMessage
    }

    public init(
        reply: String,
        payload: SessionAdjustmentPayload,
        recommendationID: String,
        previewBanner: SessionAdjustmentBannerModel?,
        status: CoachProposalStatus,
        requestID: UUID? = nil
    ) {
        self.reply = reply
        self.payload = payload
        self.recommendationID = recommendationID
        self.previewBanner = previewBanner
        self.status = status
        self.requestID = requestID
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
        contextDays: [CoachContextDay],
        thread: CoachThreadState = .empty
    ) async throws -> CoachSessionProposal {
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

        guard let gemini = provider as? GeminiProvider else {
            throw InSessionCoachError.providerUnavailable("Session adjustments require Gemini.")
        }

        let prompt = buildPrompt(
            snapshot: snapshot,
            profile: profile,
            contextDays: contextDays,
            excludedExerciseIDs: excludedExerciseIDs
        )

        let artefact = try await gemini.generateSessionAdjustment(
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

        await logProposalDiagnostics(proposal: proposal, sessionID: snapshot.session.id)
        return proposal
    }

    public func applyProposal(
        _ proposal: CoachSessionProposal,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>
    ) throws -> AppliedSessionAdjustment {
        guard proposal.requiresConfirmation else {
            throw InSessionCoachError.noApplicableChange
        }

        let applied = try applyAdjustment(
            payload: proposal.payload,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            modelVersion: proposal.payload.schemaVersion,
            recommendationID: proposal.recommendationID,
            markActedOn: true
        )

        try persistence.coachRecommendations.markActedOn(id: proposal.recommendationID)
        return applied
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
        contextDays: [CoachContextDay]
    ) async throws -> AppliedSessionAdjustment {
        let proposal = try await proposeAdjustment(
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            provider: provider,
            profile: profile,
            contextDays: contextDays
        )
        guard proposal.requiresConfirmation else {
            throw InSessionCoachError.noApplicableChange
        }
        return try applyProposal(proposal, snapshot: snapshot, excludedExerciseIDs: excludedExerciseIDs)
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
        let displayNames = try persistence.exercises.displayNames(for: Array(sessionExerciseIDs))
        let (catalog, familiarExerciseIDs) = try loadCatalog()
        let normalized = try SessionExerciseIDResolver.normalize(
            payload: stampedPayload,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: displayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs
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
        let displayNames = try persistence.exercises.displayNames(for: Array(sessionExerciseIDs))
        let (catalog, familiarExerciseIDs) = try loadCatalog()
        let normalized = try SessionExerciseIDResolver.normalize(
            payload: stampedPayload,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: displayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs
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
                requestID: requestID
            )
        }

        if !normalized.unresolvedExerciseIDs.isEmpty {
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
                requestID: requestID
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
                requestID: requestID
            )
        case .applied(let adjusted):
            guard PrescriptionDiff.exercisesChanged(from: currentPrescription, to: adjusted) else {
                return CoachSessionProposal(
                    reply: payload.reply,
                    payload: normalized.payload,
                    recommendationID: recommendation.id,
                    previewBanner: nil,
                    status: .failed(.noDiff),
                    requestID: requestID
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
                requestID: requestID
            )
        }
    }

    private func buildPrompt(
        snapshot: ActiveSessionSnapshot,
        profile: MemoryProfile,
        contextDays: [CoachContextDay],
        excludedExerciseIDs: Set<String>
    ) -> CoachPrompt {
        var context = ContextBuilder.build(
            profile: profile,
            days: CoachContextDays(recent: contextDays),
            budget: TokenBudget.maxInputTokens(for: .gemini),
            turn: .followUp
        ).contextBlock

        let exerciseIDs = snapshot.session.exercises.map(\.exerciseID)
        let displayNames = (try? persistence.exercises.displayNames(for: exerciseIDs)) ?? [:]

        let sortedExercises = snapshot.session.exercises.sorted { $0.displayOrder < $1.displayOrder }
        let exerciseLines = sortedExercises
            .enumerated()
            .map { index, exercise in
                let completed = exercise.sets.filter { $0.status == .completed }.count
                let label = ExerciseDisplayFormatter.friendlyName(
                    for: exercise.exerciseID,
                    displayNames: displayNames
                )
                let archetypeID = CoachArchetypeSupport.archetype(for: exercise.exerciseID)?.id ?? exercise.exerciseID
                return "- slot \(index + 1) | \(archetypeID) | \(label) (\(exercise.sets.count) sets, \(completed) completed)"
            }
            .joined(separator: "\n")

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

        if let notes = snapshot.session.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            context += "\n\nAthlete session note:\n\(notes)"
        }
        if !archetypeLines.isEmpty {
            context += "\n\nAllowed archetype IDs (use exact archetypeId in operations):\n\(archetypeLines)"
        }
        if !exerciseLines.isEmpty {
            context += "\n\nActive session exercises:\n\(exerciseLines)"
        }
        if !excludedExerciseIDs.isEmpty {
            let excludedArchetypes = excludedExerciseIDs.compactMap { CoachArchetypeSupport.archetype(for: $0)?.id }
            context += "\n\nExcluded archetype IDs (already swapped this session):\n"
                + excludedArchetypes.sorted().joined(separator: ", ")
        }

        return CoachPrompt(
            systemInstructions: CoachSystemPrompt.sessionAdjustmentV2,
            contextBlock: context,
            estimatedTokens: TokenBudget.estimateTokens(characterCount: context.count),
            includedDayCount: contextDays.count,
            droppedDayCount: 0
        )
    }

    private func loadCatalog() throws -> (catalog: [CatalogExercise], familiarExerciseIDs: Set<String>) {
        let rows = try persistence.exercises.fetchCatalogRows()
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day
        )
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: rows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        return (catalog, familiarExerciseIDs)
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

        let stored = try persistence.coachRecommendations.insert(
            CoachRecommendationInsert(
                scope: .session,
                workoutSessionID: sessionID,
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
            return (
                ExerciseDisplayFormatter.friendlyName(for: fromID, displayNames: names),
                ExerciseDisplayFormatter.friendlyName(for: toID, displayNames: names)
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
        case .adjustLoad:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let toExercise = adjusted.exercises.first { $0.exerciseID == exerciseID }
            let fromLabel = ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names)
            guard let toMass = toExercise?.targetMass?.kilograms else {
                throw InSessionCoachError.noApplicableChange
            }
            return (fromLabel, formatMass(toMass))
        case .adjustRPE:
            let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
            let toExercise = adjusted.exercises.first { $0.exerciseID == exerciseID }
            let fromLabel = ExerciseDisplayFormatter.friendlyName(for: exerciseID, displayNames: names)
            guard let toRPE = toExercise?.targetRPE else {
                throw InSessionCoachError.noApplicableChange
            }
            return (fromLabel, formatRPE(toRPE))
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
