import CoachLLM
import Core
import Diagnostics
import DesignSystem
import Foundation
import HealthKitIngest
import Observation
import Persistence

@MainActor
@Observable
final class ChatController {
    private(set) var messages: [StoredChatMessage] = []
    var draftText = ""
    private(set) var streamingText: String?
    private(set) var isStreaming = false
    private(set) var degradedState: CoachDegradedState?
    private(set) var isCoachAvailable = true
    private(set) var lastTurnError: String?
    var citationFailureCount: Int {
        CoachDiagnosticsStore.shared.citationFailures.count
    }
    /// Citation validation map rebuilt each turn from the evidence index sent in context.
    var citationValidation: CitationValidationMap?
    private(set) var lastFailedUserMessage: String?
    /// When true, next `sendMessage` skips persisting another user row (retry path).
    private var omitNextUserAppend = false
    private(set) var pendingChatAction: CoachChatActionProposal?
    /// Assistant message that owns the current pending confirm card (CAM-86).
    private(set) var pendingChatActionMessageID: String?
    /// Yes/no or value prompt that stays in the transcript after it is answered.
    private(set) var structuredPromptMessageID: String?
    private(set) var chatConfirmationsByMessageID: [String: CoachChatConfirmation] = [:]
    private(set) var pendingFoodMealConfirm: CoachFoodMealConfirmState?
    private(set) var isApplyingChatAction = false
    private(set) var applyProgressStep: String?
    private(set) var isPreparingFoodMealConfirm = false
    private(set) var chatProgressTitle: String?
    private(set) var chatProgressCompletedSteps: [String] = []
    private(set) var chatProgressStep: String?
    private(set) var handoffGeneration = 0
    private(set) var pendingHandoffPrompt: String?
    /// Set when the user's message is a plan-builder request; ChatView presents the flow.
    private(set) var pendingPlanBuilderLaunch = false
    /// Memory refinements extracted from the most recent session, awaiting confirmation.
    private(set) var pendingMemoryRefinements: [MemoryRefinementEntry] = []
    /// Assistant message the background extraction was taken from.
    private(set) var memoryRefinementSourceMessageID: String?
    /// Applied coach writes keyed by the assistant message that confirmed them.
    private(set) var undoableActionsByMessageID: [String: CoachAppliedAction] = [:]
    /// Last schedule write the athlete confirmed (suppress identical re-proposals).
    private var lastAppliedSchedulePayload: ScheduleAdjustmentPayload?
    /// Date of the last refinement extraction for debouncing.
    private var lastRefinementExtractionDate: Date?
    /// `navigate` held until the athlete confirms a same-turn write.
    private var pendingNavigateTab: AppTab?
    /// Recent meal_query context used to validate edit/delete proposals.
    private var lastMealQueryContext: MealQueryContext?
    private var mutationLedger: CoachMutationLedger {
        CoachMutationLedger(metadata: persistence.appMetadata)
    }

    private let persistence: PersistenceStore
    private let providerPreferences: ProviderPreferencesStore
    private var streamTask: Task<Void, Never>?
    private var isFoodDictationTurn = false
    /// Coalesce token UI updates so Chat does not rebuild on every chunk.
    @ObservationIgnored private var pendingStreamingText: String?
    @ObservationIgnored private var lastStreamingUIPublish = Date.distantPast
    @ObservationIgnored private var hasHydratedHistory = false
    private static let streamingUIInterval: TimeInterval = 0.05
    private static let cloudFeaturesOffMessage =
        "Cloud features are off. Turn them on in Settings to use Coach."
    private static let weekdayMealQueryRequiredMessage =
        "I need to look up that weekday in your diary first. Ask what was logged (for example, Sunday dinner), then I can delete or copy using the ISO day from the results."

    init(
        persistence: PersistenceStore,
        providerPreferences: ProviderPreferencesStore = ProviderPreferencesStore()
    ) {
        self.persistence = persistence
        self.providerPreferences = providerPreferences
    }

    func onAppear() async {
        // Bootstrap may hydrate at launch; skip duplicate GRDB load when Chat tab opens.
        if !hasHydratedHistory {
            loadHistory()
            hasHydratedHistory = true
        }
        await refreshAvailability()
    }

    func onDisappear() {
        // Keep streaming when switching tabs so Chat and in-session coach can run in parallel.
    }

    func retryLastTurn() {
        guard let lastFailedUserMessage, !isStreaming else { return }
        // User row already persisted from the failed attempt; do not append a duplicate.
        omitNextUserAppend = true
        draftText = lastFailedUserMessage
        send()
    }

    func loadHistory() {
        do {
            messages = try persistence.chat.fetchRecent(limit: ChatStore.chatUILimit)
            reloadUndoableActions()
            reloadChatConfirmations()
        } catch {
            degradedState = CoachFailurePolicy.degradedState(for: error)
        }
    }

    func clearConversation() {
        guard !isStreaming, !isApplyingChatAction else { return }
        streamTask?.cancel()
        streamTask = nil
        do {
            try persistence.chat.clear()
            try? persistence.coachChatConfirmations.clearAll()
            messages = []
            pendingChatAction = nil
            pendingChatActionMessageID = nil
            chatConfirmationsByMessageID = [:]
            pendingFoodMealConfirm = nil
            pendingNavigateTab = nil
            lastTurnError = nil
            lastFailedUserMessage = nil
            streamingText = nil
            citationValidation = nil
            pendingMemoryRefinements = []
            memoryRefinementSourceMessageID = nil
            undoableActionsByMessageID = [:]
            lastAppliedSchedulePayload = nil
            lastRefinementExtractionDate = nil
            clearChatProgress()
            CoachDiagnosticsStore.shared.clear()
            Task {
                await ProviderRegistry.shared.resetAllThreads()
            }
        } catch {
            lastTurnError = "Could not clear chat."
        }
    }

    func refreshAvailability() async {
        guard CloudFeatureConsentPreferences.shared.isConsented else {
            markCloudFeaturesUnavailable()
            return
        }

        let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)
        let availability = await provider.availability()
        isCoachAvailable = availability.isAvailable
        if availability.isAvailable {
            degradedState = nil
        } else if case .unavailable(let label, let helpText) = availability {
            degradedState = CoachDegradedState(
                mode: .engineOnly,
                reason: .providerUnavailable,
                userMessage: helpText ?? label
            )
        }
    }

    private func markCloudFeaturesUnavailable() {
        isCoachAvailable = false
        degradedState = CoachDegradedState(
            mode: .engineOnly,
            reason: .providerUnavailable,
            userMessage: Self.cloudFeaturesOffMessage
        )
    }

    private func isPendingWorkoutStart(_ proposal: CoachChatActionProposal?) -> Bool {
        if case .workoutStart = proposal?.kind { return true }
        return false
    }

    func send() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if isStreaming {
            lastTurnError = "Coach is still responding. Wait a moment and try again."
            return
        }
        if CoachChatIntent.looksLikeClearChat(trimmed) {
            draftText = ""
            clearConversation()
            return
        }
        if CoachChatIntent.looksLikePlanBuilderRequest(trimmed) {
            draftText = ""
            pendingPlanBuilderLaunch = true
            return
        }
        if CoachActivityGate.shared.isBlocked(for: .chat) {
            lastTurnError = CoachActivityGate.shared.blockingMessage(for: .chat)
            return
        }
        if case .workoutStart = pendingChatAction?.kind,
           CoachChatIntent.confirmsPendingWorkoutStart(trimmed) {
            draftText = ""
            confirmChatAction()
            return
        }

        draftText = ""
        streamTask = Task { @MainActor in
            await sendMessage(trimmed)
        }
    }

    func sendFoodDictation(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isStreaming else {
            lastTurnError = "Coach is still responding. Wait a moment and try again."
            return
        }
        if CoachActivityGate.shared.isBlocked(for: .chat) {
            lastTurnError = CoachActivityGate.shared.blockingMessage(for: .chat)
            return
        }

        lastTurnError = nil
        dismissFoodMealConfirm()
        draftText = ""
        streamTask?.cancel()
        isFoodDictationTurn = true
        streamTask = Task { @MainActor in
            await sendMessage(
                trimmed,
                coachUserMessage: CoachSystemPrompt.foodDictationCoachMessage(transcript: trimmed)
            )
        }
    }

    func dismissFoodMealConfirm() {
        pendingFoodMealConfirm = nil
        pendingNavigateTab = nil
        lastTurnError = nil
    }

    func confirmFoodMeal(estimate: MealEstimate, name: String, bucket: MealBucket) {
        guard let pending = pendingFoodMealConfirm, !isApplyingChatAction else { return }
        lastTurnError = nil
        Task {
            await applyFoodMealConfirm(
                pending: pending,
                estimate: estimate,
                name: name,
                bucket: bucket
            )
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isFoodDictationTurn = false
        if isStreaming {
            isStreaming = false
            streamingText = nil
        }
    }

    func requestCoachHandoff(prompt: String) {
        pendingHandoffPrompt = prompt
        handoffGeneration += 1
    }

    func consumeHandoffPromptIfNeeded() {
        guard let prompt = pendingHandoffPrompt else { return }
        pendingHandoffPrompt = nil
        draftText = prompt
    }

    func confirmChatAction() {
        guard let proposal = pendingChatAction, !isApplyingChatAction else { return }
        lastTurnError = nil
        Task {
            await applyChatAction(proposal)
        }
    }

    func dismissChatAction() {
        if case let .sessionAdjustment(proposal) = pendingChatAction?.kind {
            TrainBootstrap.sessionController.dismissChatSessionProposal(proposal)
        }
        let cancelLabel = pendingChatAction?.cancelLabel ?? "Cancel"
        resolvePendingChatConfirmation(outcome: .dismissed, selectedLabel: cancelLabel)
        pendingChatAction = nil
        pendingChatActionMessageID = nil
        pendingNavigateTab = nil
        lastTurnError = nil
    }

    func dismissPlanBuilderLaunch() {
        pendingPlanBuilderLaunch = false
    }

    func acceptMemoryRefinements() {
        guard !pendingMemoryRefinements.isEmpty else { return }
        Task { @MainActor in
            do {
                _ = try await HelmActionRuntime.perform(
                    .memory(.applyRefinements(
                        pendingMemoryRefinements,
                        today: HelmDay.day(for: Date(), calendar: .current)
                    )),
                    after: .coach
                )
                pendingMemoryRefinements = []
                memoryRefinementSourceMessageID = nil
            } catch {
                lastTurnError = error.localizedDescription
            }
        }
    }

    func dismissMemoryRefinements() {
        pendingMemoryRefinements = []
        memoryRefinementSourceMessageID = nil
    }

    func undoableAction(for messageID: String) -> CoachAppliedAction? {
        undoableActionsByMessageID[messageID]
    }

    func undoAppliedAction(id: UUID) {
        Task { @MainActor in
            do {
                guard let action = try persistence.coachAppliedActions.fetch(id: id),
                      action.isUndoable
                else { return }
                switch action.kind {
                case .mealDelete:
                    let data = Data(action.snapshotJSON.utf8)
                    let snapshot = try JSONDecoder().decode(MealDeleteSnapshot.self, from: data)
                    try await restoreDeletedMeals(snapshot)
                case .scheduleAdjustment:
                    let data = Data(action.snapshotJSON.utf8)
                    let snapshot = try JSONDecoder().decode(ScheduleOverrideSnapshot.self, from: data)
                    try await restoreScheduleOverrides(snapshot)
                    lastAppliedSchedulePayload = nil
                }
                try persistence.coachAppliedActions.markUndone(id: id)
                undoableActionsByMessageID[action.messageID] = nil
            } catch {
                lastTurnError = error.localizedDescription
            }
        }
    }

    func reportSurfaceError(_ message: String) {
        lastTurnError = message
    }

    private func applyFoodMealConfirm(
        pending: CoachFoodMealConfirmState,
        estimate: MealEstimate,
        name: String,
        bucket: MealBucket
    ) async {
        isApplyingChatAction = true
        applyProgressStep = "Writing to diary…"
        defer {
            isApplyingChatAction = false
            applyProgressStep = nil
        }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = trimmedName.isEmpty ? estimate.description : trimmedName
            let today = HelmDay.day(for: Date(), calendar: .current)
            let loggedAt = MealLogInstant.loggedAt(
                for: pending.helmDay,
                bucket: bucket,
                today: today
            )
            let mealID = UUID()
            let records = estimate.lineItems.enumerated().map { index, item in
                MealLineItemTemplateMapping.record(
                    from: item,
                    mealID: mealID,
                    sortOrder: index
                )
            }

            if records.isEmpty {
                _ = try await HelmActionRuntime.perform(
                    .meal(.logQuickAdd(
                        kilocalories: estimate.caloriesKcal,
                        proteinG: estimate.proteinG,
                        carbsG: estimate.carbsG,
                        fatG: estimate.fatG,
                        label: resolvedName,
                        bucket: bucket,
                        loggedAt: loggedAt,
                        helmDay: pending.helmDay,
                        mealID: mealID.uuidString
                    )),
                    after: .coach
                )
            } else {
                _ = try await HelmActionRuntime.perform(
                    .meal(.logComposite(
                        name: resolvedName,
                        bucket: bucket,
                        lineItems: records,
                        loggedAt: loggedAt,
                        helmDay: pending.helmDay,
                        mealID: mealID.uuidString,
                        source: .manual
                    )),
                    after: .coach
                )
            }

            pendingFoodMealConfirm = nil
            lastTurnError = nil
            applyDeferredNavigateIfNeeded()
        } catch {
            lastTurnError = error.localizedDescription
            pendingFoodMealConfirm = nil
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatFoodMeal", error: error)
        }
    }

    private func applyChatAction(_ proposal: CoachChatActionProposal) async {
        isApplyingChatAction = true
        applyProgressStep = "Applying change…"
        defer {
            isApplyingChatAction = false
            applyProgressStep = nil
        }

        do {
            if case let .foodLog(payload) = proposal.kind,
               let validationError = FoodLogProposalValidator.validate(
                   payload: payload,
                   queryContext: lastMealQueryContext,
                   persistence: persistence
               ) {
                lastTurnError = validationError.recoveryMessage
                return
            }

            if let idempotencyKey = mutationIdempotencyKey(for: proposal),
               mutationLedger.wasApplied(idempotencyKey) {
                resolvePendingChatConfirmation(
                    outcome: .confirmed,
                    selectedLabel: proposal.confirmLabel
                )
                pendingChatAction = nil
                pendingChatActionMessageID = nil
                lastTurnError = nil
                applyDeferredNavigateIfNeeded()
                return
            }

            switch proposal.kind {
            case let .foodLog(payload):
                applyProgressStep = "Writing to diary…"
                let deleteSnapshot = payload.action == .delete ? try snapshotMeals(for: payload) : nil
                let result = try await HelmActionRuntime.perform(
                    .meal(.fromCoachPayload(payload, now: Date())),
                    after: .coach
                )
                if let deleteSnapshot {
                    persistMealDeleteUndo(snapshot: deleteSnapshot)
                }
                if let day = result.nutritionDay {
                    NutritionBootstrap.refreshNutrition(for: day)
                }
                if let echo = result.diaryOpEcho {
                    appendDiaryOpEcho(echo)
                }
            case let .mealCopy(payload):
                applyProgressStep = "Copying meal…"
                let today = HelmDay.day(for: Date(), calendar: .current)
                guard let resolved = MealCopyCommandApplier.resolvedDays(payload, today: today) else {
                    throw ManualMealError.invalidQuickAdd
                }
                if try NutritionBootstrap.mealRepeatService.wouldDuplicateCopy(
                    from: resolved.source,
                    bucket: resolved.sourceBucket,
                    to: resolved.target,
                    targetBucket: resolved.targetBucket
                ) {
                    throw MealRepeatError.duplicateCopy
                }
                let result = try await HelmActionRuntime.perform(
                    .copyMeal(HelmCopyMealCommand(
                        sourceDay: resolved.source,
                        sourceBucket: resolved.sourceBucket,
                        targetDay: resolved.target,
                        targetBucket: resolved.targetBucket
                    )),
                    after: .coach
                )
                if let day = result.nutritionDay {
                    NutritionBootstrap.refreshNutrition(for: day)
                }
                if let echo = result.diaryOpEcho {
                    appendDiaryOpEcho(echo)
                }
            case let .memoryAdjustment(payload):
                applyProgressStep = "Updating Memory…"
                let today = HelmDay.day(for: Date(), calendar: .current)
                _ = try await HelmActionRuntime.perform(
                    .memory(.fromCoachPayload(payload, today: today)),
                    after: .coach
                )
            case let .workoutStart(payload):
                applyProgressStep = "Preparing session…"
                let today = HelmDay.day(for: .now, calendar: .current)
                try await HelmActionRuntime.startFromCoachPayload(
                    payload,
                    helmDay: today,
                    persistence: persistence
                )
                CoachApplyMomentStore.shared.play()

                let messageID = messages.last(where: { $0.role == .assistant })?.id ?? UUID().uuidString
                let payloadJSON = (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let record = CoachAdviceRecord(
                    messageID: messageID,
                    adviceType: .workoutStart,
                    schemaVersion: payload.schemaVersion,
                    prescribedPayload: payloadJSON,
                    state: .pending,
                    helmDay: today.formatted
                )
                do {
                    try persistence.coachAdviceRecords.insert(record)
                    try persistence.coachAdviceRecords.supersedePending(
                        type: .workoutStart,
                        excluding: messageID
                    )
                } catch {
                    CoachDiagnosticsStore.shared.recordFailure(surface: "coachAdviceRecord", error: error)
                }
            case let .settingsAdjustment(payload):
                applyProgressStep = "Updating plan…"
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.fromCoachPayload(payload)),
                    after: .coach
                )
            case let .scheduleAdjustment(payload):
                applyProgressStep = "Updating week…"
                let priorOverrides = (try? persistence.scheduleOverrides.load()) ?? .empty
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.scheduleAdjustment(payload)),
                    after: .coach
                )
                persistScheduleUndo(
                    prior: priorOverrides,
                    caption: proposal.detail
                )
                lastAppliedSchedulePayload = payload
            case let .reactiveDeload(payload):
                applyProgressStep = "Updating plan…"
                let action: HelmReactiveDeloadAction = payload.action == .confirm ? .confirm : .dismiss
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.reactiveDeload(action)),
                    after: .coach
                )
            case let .planRegenerate(payload):
                applyProgressStep = "Regenerating…"
                let today = HelmDay.day(for: .now, calendar: .current)
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.regenerateToday(today, ignoreReadinessTrim: payload.ignoreReadinessTrim)),
                    after: .coach
                )
            case let .sessionAdjustment(sessionProposal):
                applyProgressStep = "Updating session…"
                _ = try await TrainBootstrap.sessionController.applySessionProposal(sessionProposal)
            case .workoutDiscard:
                applyProgressStep = "Discarding workout…"
                await TrainBootstrap.sessionController.discardWorkout()
            }
            if let idempotencyKey = mutationIdempotencyKey(for: proposal) {
                try? mutationLedger.recordApplied(idempotencyKey)
            }
            resolvePendingChatConfirmation(
                outcome: .confirmed,
                selectedLabel: proposal.confirmLabel
            )
            pendingChatAction = nil
            pendingChatActionMessageID = nil
            lastTurnError = nil
            applyDeferredNavigateIfNeeded()
        } catch let duplicate as MealRepeatError where duplicate == .duplicateCopy {
            lastTurnError = "That meal is already on the target day. Pick another day or bucket."
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatAction", error: duplicate)
        } catch {
            lastTurnError = error.localizedDescription
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatAction", error: error)
        }
    }

    private func mutationIdempotencyKey(for proposal: CoachChatActionProposal) -> String? {
        let today = HelmDay.day(for: Date(), calendar: .current)
        switch proposal.kind {
        case let .foodLog(payload):
            let day = FoodLogCommandApplier.resolvedHelmDay(from: payload, now: Date())
            return CoachMutationIdempotency.key(forFoodLog: payload, resolvedHelmDay: day)
        case let .mealCopy(payload):
            guard let resolved = MealCopyCommandApplier.resolvedDays(payload, today: today) else {
                return nil
            }
            return CoachMutationIdempotency.key(
                forMealCopy: HelmCopyMealCommand(
                    sourceDay: resolved.source,
                    sourceBucket: resolved.sourceBucket,
                    targetDay: resolved.target,
                    targetBucket: resolved.targetBucket
                )
            )
        case let .sessionAdjustment(sessionProposal):
            guard let sessionID = TrainBootstrap.sessionController.store.snapshot?.session.id else {
                return nil
            }
            return CoachMutationIdempotency.key(forSession: sessionProposal, sessionID: sessionID)
        case .workoutStart, .memoryAdjustment, .settingsAdjustment, .scheduleAdjustment,
             .reactiveDeload, .planRegenerate, .workoutDiscard:
            return nil
        }
    }

    func answerStructuredPrompt(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, structuredPromptMessageID != nil else { return }
        let sends = trimmed == "Yes" || trimmed == "No"
        resolveStructuredPrompt(label: trimmed)
        guard sends, !isStreaming else { return }
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            await sendMessage(trimmed)
        }
    }

    private func sendMessage(_ text: String, coachUserMessage: String? = nil) async {
        if structuredPromptMessageID != nil {
            resolveStructuredPrompt(label: text)
        }
        guard CloudFeatureConsentPreferences.shared.isConsented else {
            let wasFoodDictation = isFoodDictationTurn
            isFoodDictationTurn = false
            markCloudFeaturesUnavailable()
            lastTurnError = wasFoodDictation ? Self.cloudFeaturesOffMessage : nil
            return
        }

        let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)
        let availability = await provider.availability()
        guard availability.isAvailable else {
            let wasFoodDictation = isFoodDictationTurn
            isFoodDictationTurn = false
            isCoachAvailable = false
            if case .unavailable(let label, let helpText) = availability {
                degradedState = CoachDegradedState(
                    mode: .engineOnly,
                    reason: .providerUnavailable,
                    userMessage: helpText ?? label
                )
            } else {
                degradedState = CoachDegradedState(
                    mode: .engineOnly,
                    reason: .providerUnavailable,
                    userMessage: "Coach is unavailable. Numbers and logging still work."
                )
            }
            // Nutrition describe sheet only watches lastTurnError - surface key/provider gaps there.
            if wasFoodDictation {
                lastTurnError = degradedState?.userMessage
                    ?? "Coach is unavailable. Check Coach settings and try again."
            }
            return
        }

        isCoachAvailable = true
        degradedState = nil
        lastTurnError = nil
        lastFailedUserMessage = text
        // Only drop a pending workout-start card when the athlete changes topic.
        // Greetings must not silently clear schedule/memory confirms (CAM-37).
        if CoachChatIntent.clearsPendingWorkoutStart(text),
           case .workoutStart = pendingChatAction?.kind {
            abandonPendingChatAction(selectedLabel: pendingChatAction?.cancelLabel ?? "Skipped")
        }
        if CoachChatIntent.dismissesPendingConfirm(text) || CoachChatIntent.refusesWorkoutStart(text) {
            abandonPendingChatAction(selectedLabel: "Cancel")
        }
        if coachUserMessage != nil {
            beginFoodDictationProgress(step: "Sending to coach…")
        } else {
            clearChatProgress()
        }
        CoachActivityGate.shared.begin(.chat)
        defer { CoachActivityGate.shared.end(.chat) }

        do {
            let isFoodDictation = coachUserMessage != nil
            if !isFoodDictation {
                if omitNextUserAppend {
                    omitNextUserAppend = false
                } else {
                    let userMessage = try persistence.chat.append(
                        ChatMessageInsert(
                            role: .user,
                            text: text,
                            promptVersion: CoachPromptVersion.chatV1.rawValue
                        )
                    )
                    messages.append(userMessage)
                    trimVisibleChatHistory()
                }
            }
            navigateIfRequested(from: text)

            // Update coach style profile from this athlete message.
            var profile = try persistence.memoryProfile.load()
            CoachStyleDetector.update(
                profile: &profile.globalStyle,
                from: text, turnIndex: messages.count
            )
            try await HelmActionRuntime.perform(
                .memory(.replaceProfile(profile)),
                after: .none
            )
            
            let endDay = HelmDay.day(for: .now, calendar: .current)
            let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
            citationValidation = CitationValidationMap(
                evidenceRecords: contextDays.evidence,
                topics: ResourceModuleIndex.shared?.filteredTopics(
                    moduleIDs: profile.activeModules
                ) ?? []
            )
            var thread = CoachThreadState(
                messages: isFoodDictation
                    ? []
                    : messages.map { CoachMessage(role: $0.role, text: $0.text) }
            )

            // Trigger compaction when thread exceeds 20 messages.
            if thread.messages.count > 20 {
                let track = thread.messages.count - (thread.summary?.compressedMessageCount ?? 0)
                let minSinceCompact = thread.summary != nil ? 5 : 20
                if track >= 5 {
                    thread = try await compactThread(thread, provider: provider)
                }
            }

            thread = thread.windowed()
            let turn: ContextTurn = thread.isFollowUp ? .followUp : .initial
            let reserved = TokenBudget.estimateTokens(
                characterCount: thread.messages.reduce(0) { $0 + $1.text.count }
            ) + 2_048
            let budget = max(
                4_096,
                TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider) - reserved
            )
            if coachUserMessage == nil,
               CoachChatIntent.shouldRouteChatToSessionCoach(
                text,
                sessionIsLive: TrainBootstrap.sessionController.hasActiveSession
               ) {
                try await completeSessionCoachTurn(
                    text: text,
                    provider: provider,
                    profile: profile,
                    contextDays: contextDays,
                    thread: thread
                )
                return
            }

            let lastAssistant = messages.last(where: { $0.role == .assistant })?.text
            let earlierUser = messages.dropLast().last(where: { $0.role == .user })?.text
            let prompt = makeCoachPrompt(
                profile: profile,
                days: contextDays,
                budget: budget,
                turn: turn
            )

            isStreaming = true
            streamingText = ""
            if coachUserMessage != nil {
                chatProgressStep = "Coach is estimating your meal…"
            }

            let providerUserMessage = coachUserMessage
                ?? CoachChatIntent.athleteTurn(
                    text,
                    earlierUser: earlierUser,
                    earlierAssistant: lastAssistant
                )
            var assembledTurn: AssembledCoachTurn
            var didProseHeal = false
            do {
                assembledTurn = try await streamAssistantTurn(
                    provider: provider,
                    systemInstructions: prompt.systemInstructions,
                    contextBlock: prompt.contextBlock,
                    userMessage: providerUserMessage,
                    thread: thread,
                    allowEmptyRetry: false,
                    freshnessSuffix: prompt.freshnessSuffix
                )
            } catch let error as CoachStructuredOutputError where error == .emptyResponse {
                if coachUserMessage == nil {
                    await logCoachHeal(stage: "emptyProseRetry", callNames: "none", userText: text)
                    didProseHeal = true
                    assembledTurn = try await streamAssistantTurn(
                        provider: provider,
                        systemInstructions: prompt.systemInstructions,
                        contextBlock: prompt.contextBlock,
                        userMessage: Self.proseOnlyNudge(providerUserMessage),
                        thread: thread,
                        allowEmptyRetry: false,
                        freshnessSuffix: prompt.freshnessSuffix
                    )
                } else {
                    throw error
                }
            }

            // CAM-85: past-tense food reports that skipped food_log get one silent re-prompt.
            if !isFoodDictationTurn,
               coachUserMessage == nil,
               CoachChatIntent.looksLikeFoodLog(text),
               !hasDecodableFoodLog(in: assembledTurn) {
                streamingText = "Logging meal…"
                do {
                    let nudged = try await streamAssistantTurn(
                        provider: provider,
                        systemInstructions: prompt.systemInstructions,
                        contextBlock: prompt.contextBlock,
                        userMessage: """
                        \(providerUserMessage)

                        [System: Athlete reported eating something. You MUST call food_log this turn with estimated macros. Do not only acknowledge.]
                        """,
                        thread: thread,
                        allowEmptyRetry: false,
                        freshnessSuffix: prompt.freshnessSuffix
                    )
                    if hasDecodableFoodLog(in: nudged)
                        || !CoachChatTextFormatter.userFacingText(from: nudged.text)
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        assembledTurn = nudged
                    }
                } catch {
                    // Keep first-turn output; soft error handled below if still no food_log.
                }
            }

            // Food dictation must stay on food_log.v1 - do not hijack into diary query follow-ups.
            let querySource = assembledTurn
            let mealQuery = isFoodDictationTurn ? nil : catalogQuery(
                named: .mealQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.meal,
                parseJSON: MealQueryPayloadParser.parse,
                infer: CoachChatIntent.inferredMealQuery
            )
            let recoveryQuery = catalogQuery(
                named: .recoveryQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.recovery,
                parseJSON: RecoveryQueryPayloadParser.parse,
                infer: CoachChatIntent.inferredRecoveryQuery
            )
            let calendarQuery = catalogQuery(
                named: .calendarQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.calendar,
                parseJSON: CalendarQueryPayloadParser.parse,
                infer: { CoachChatIntent.inferredCalendarQuery(from: $0) }
            )
            let trendsQuery = catalogQuery(
                named: .trendsQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.trends,
                parseJSON: TrendsQueryPayloadParser.parse,
                infer: CoachChatIntent.inferredTrendsQuery
            )
            let patternQuery = catalogQuery(
                named: .patternQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.pattern,
                parseJSON: PatternQueryPayloadParser.parse,
                infer: CoachChatIntent.inferredPatternQuery
            )
            let workoutQuery = catalogQuery(
                named: .workoutQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.workout,
                parseJSON: WorkoutQueryPayloadParser.parse,
                infer: { CoachChatIntent.inferredWorkoutQuery(from: $0) }
            )
            let nutritionQuery = catalogQuery(
                named: .nutritionQuery,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.nutrition,
                parseJSON: NutritionQueryPayloadParser.parse,
                infer: CoachChatIntent.inferredNutritionQuery
            )
            let contextRefresh = catalogQuery(
                named: .contextRefresh,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.contextRefresh,
                parseJSON: ContextRefreshPayloadParser.parse,
                infer: { _ in nil }
            )
            let healthSync = catalogQuery(
                named: .healthSync,
                from: querySource,
                userText: text,
                decode: CoachCatalogQueryDecoder.healthSync,
                parseJSON: HealthSyncPayloadParser.parse,
                infer: { _ in nil }
            )

            let explicitQueries = CoachCatalogQueryResolver.explicitQueryNames(
                in: querySource.functionCalls
            )
            let inferredBodyFatQuery: TrendsQueryPayload? = {
                guard CoachChatIntent.inferredTrendsQuery(from: text)?.queryType == .bodyFat else {
                    return nil
                }
                return TrendsQueryPayload(queryType: .bodyFat, lookbackDays: 90)
            }()
            if CoachCatalogQueryResolver.shouldRunHealthSyncFollowUp(
                inferred: false,
                explicitQueries: explicitQueries
            ), let healthSync {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runHealthSyncFollowUp(
                        payload: healthSync,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if let inferredBodyFatQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runTrendsQueryFollowUp(
                        query: inferredBodyFatQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.mealQuery, explicitQueries: explicitQueries),
               let mealQuery {
                assembledTurn = await mealQueryFollowUpOrFallback(
                    current: assembledTurn,
                    query: mealQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay
                )
            } else if CoachCatalogQueryResolver.shouldFollowUp(.recoveryQuery, explicitQueries: explicitQueries),
                      let recoveryQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runRecoveryQueryFollowUp(
                        query: recoveryQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text,
                        cachedContextDays: contextDays
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.calendarQuery, explicitQueries: explicitQueries),
                      let calendarQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runCalendarQueryFollowUp(
                        query: calendarQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.trendsQuery, explicitQueries: explicitQueries),
                      let trendsQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runTrendsQueryFollowUp(
                        query: trendsQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.patternQuery, explicitQueries: explicitQueries),
                      let patternQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runPatternQueryFollowUp(
                        query: patternQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.workoutQuery, explicitQueries: explicitQueries),
                      let workoutQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runWorkoutQueryFollowUp(
                        query: workoutQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.nutritionQuery, explicitQueries: explicitQueries),
                      let nutritionQuery {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runNutritionQueryFollowUp(
                        query: nutritionQuery,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text
                    )
                }
            } else if CoachCatalogQueryResolver.shouldFollowUp(.contextRefresh, explicitQueries: explicitQueries),
                      let contextRefresh {
                assembledTurn = try await followUpOrKeepCurrent(assembledTurn) {
                    try await runContextRefreshFollowUp(
                        payload: contextRefresh,
                        provider: provider,
                        profile: profile,
                        endDay: endDay,
                        priorAssembled: assembledTurn.text,
                        cachedContextDays: contextDays
                    )
                }
            }

            let forceWorkoutStartCard = CoachChatIntent.shouldForceWorkoutStartCard(
                text,
                lastAssistant: lastAssistant
            )
            if forceWorkoutStartCard,
               needsStructuredWorkoutStart(
                assembled: assembledTurn.text,
                functionCalls: assembledTurn.functionCalls,
                userText: text
               )
            {
                do {
                    assembledTurn = keepIfFollowUpEmpty(
                        assembledTurn,
                        next: try await runStructuredWorkoutStart(
                            provider: provider,
                            profile: profile,
                            contextDays: contextDays,
                            thread: thread,
                            userText: text,
                            priorAssembled: assembledTurn.text
                        )
                    )
                } catch let error as CoachProviderError {
                    if case .unavailable = error {
                        // Keep the streamed turn when this provider has no structured start.
                    } else {
                        throw error
                    }
                }
            }

            let wasFoodDictation = isFoodDictationTurn
            var pendingAction: CoachChatActionProposal?
            let parsedFoodPayload = CoachChatActionParser.foodLogPayload(from: assembledTurn.functionCalls)
                ?? FoodLogPayloadParser.parse(from: assembledTurn.text)
            let foodPayload = parsedFoodPayload.map { SpokenDrinkLog.corrected($0, spoken: text) }
            if wasFoodDictation,
               let foodPayload,
               foodPayload.action == .log {
                isFoodDictationTurn = false
                let bucket = resolvedFoodLogBucket(foodPayload.bucket)
                let helmDay = CoachChatIntent.resolvedChatFoodHelmDay(
                    userText: text,
                    payloadDay: foodPayload.helmDay,
                    nutritionTabVisible: AppTabRouter.shared.selectedTab == .nutrition,
                    viewedNutritionDay: NutritionBootstrap.lastViewedHelmDay?.formatted
                )
                isPreparingFoodMealConfirm = true
                chatProgressCompletedSteps = ["Coach estimated your meal"]
                let usesCofid = NutritionPreferencesStore.shared.isAIMealCofidGroundingEnabled()
                chatProgressStep = usesCofid ? "Matching ingredients to CoFID…" : "Preparing meal confirm…"
                await Task.yield()
                let estimate = FoodLogMealGrounding.groundedEstimate(
                    from: foodPayload,
                    usesCofidGrounding: usesCofid
                )
                isPreparingFoodMealConfirm = false
                clearChatProgress()
                pendingFoodMealConfirm = CoachFoodMealConfirmState(
                    estimate: estimate,
                    bucket: bucket,
                    helmDay: helmDay,
                    coachReply: foodPayload.reply
                )
                abandonPendingChatAction(selectedLabel: "Skipped")
                pendingAction = nil
            } else {
                isFoodDictationTurn = false
                clearChatProgress()
                pendingAction = CoachChatActionParser.proposal(
                    from: assembledTurn.text,
                    functionCalls: assembledTurn.functionCalls
                )
                if case let .foodLog(payload) = pendingAction?.kind {
                    let nutritionTabVisible = AppTabRouter.shared.selectedTab == .nutrition
                    let viewedNutritionDay = NutritionBootstrap.lastViewedHelmDay?.formatted
                    let day = CoachChatIntent.resolvedChatFoodHelmDay(
                        userText: text,
                        payloadDay: payload.helmDay,
                        nutritionTabVisible: nutritionTabVisible,
                        viewedNutritionDay: viewedNutritionDay
                    )
                    let resolvedPayload = payload.replacingHelmDay(day.formatted)
                    if payload.action == .delete || payload.action == .edit,
                       CoachChatIntent.shouldForceMealQueryForWeekdayMealOp(
                           userText: text,
                           mealQueryDay: lastMealQueryContext?.helmDay,
                           mealQueryIsFresh: lastMealQueryContext?.isFresh() ?? false,
                           nutritionTabVisible: nutritionTabVisible,
                           viewedNutritionDay: viewedNutritionDay
                       ) {
                        pendingAction = nil
                        assembledTurn = AssembledCoachTurn(
                            text: Self.weekdayMealQueryRequiredMessage,
                            functionCalls: []
                        )
                    } else if CoachChatIntent.weekdayConflictsWithPayloadDay(
                        userText: text,
                        payloadDay: resolvedPayload.helmDay
                    ) {
                        pendingAction = nil
                        assembledTurn = AssembledCoachTurn(
                            text: Self.weekdayMealQueryRequiredMessage,
                            functionCalls: []
                        )
                    } else if let validationError = FoodLogProposalValidator.validate(
                        payload: resolvedPayload,
                        queryContext: lastMealQueryContext,
                        persistence: persistence
                    ) {
                        pendingAction = nil
                        assembledTurn = AssembledCoachTurn(
                            text: validationError.recoveryMessage,
                            functionCalls: []
                        )
                    } else {
                        pendingAction = CoachChatActionParser.proposal(
                            fromFoodLog: resolvedPayload
                        )
                    }
                }
                if case let .mealCopy(payload) = pendingAction?.kind {
                    let nutritionTabVisible = AppTabRouter.shared.selectedTab == .nutrition
                    let viewedNutritionDay = NutritionBootstrap.lastViewedHelmDay?.formatted
                    if CoachChatIntent.shouldForceMealQueryForWeekdayMealOp(
                        userText: text,
                        mealQueryDay: lastMealQueryContext?.helmDay,
                        mealQueryIsFresh: lastMealQueryContext?.isFresh() ?? false,
                        nutritionTabVisible: nutritionTabVisible,
                        viewedNutritionDay: viewedNutritionDay
                    ) || CoachChatIntent.weekdayConflictsWithPayloadDay(
                        userText: text,
                        payloadDay: payload.sourceHelmDay
                    ) {
                        pendingAction = nil
                        assembledTurn = AssembledCoachTurn(
                            text: Self.weekdayMealQueryRequiredMessage,
                            functionCalls: []
                        )
                    }
                }
                if CoachChatIntent.suppressesWriteProposals(text) {
                    // Drop this turn's writes; keep any prior confirm card (CAM-37).
                    pendingAction = nil
                } else {
                    if case let .scheduleAdjustment(payload) = pendingAction?.kind {
                        let today = HelmDay.day(for: Date(), calendar: .current)
                        let matchesLast = lastAppliedSchedulePayload.map {
                            ScheduleOverrideApplier.sameIntent($0, payload)
                        } ?? false
                        if matchesLast
                            || ScheduleOverrideApplier.isRedundant(
                                payload,
                                persistence: persistence,
                                today: today
                            ) {
                            pendingAction = nil
                        } else if ScheduleOverrideApplier.conflictsWithPrescribedSlot(
                            payload,
                            persistence: persistence,
                            today: today
                        ), !CoachChatIntent.looksLikeScheduleOverrideIntent(text) {
                            // Unsolicited pin/swap/defer vs today_slot (CAM-111).
                            pendingAction = nil
                            assembledTurn.functionCalls.removeAll {
                                $0.name == CoachCatalogToolName.scheduleAdjustment.rawValue
                            }
                            let targetDay = HelmDay(formatted: payload.helmDay ?? "") ?? today
                            let slot = ScheduleOverrideApplier.prescribedSlotLabel(
                                on: targetDay,
                                persistence: persistence,
                                today: today
                            )
                            if CoachChatIntent.looksLikeSchedulePinAnnouncement(assembledTurn.text)
                                || payload.action == .pinDay
                                || payload.action == .deferKinds
                                || payload.action == .swapDays
                            {
                                assembledTurn.text = CoachChatIntent.unsolicitedScheduleOverrideReply(
                                    prescribedSlot: slot
                                )
                            }
                            await logCoachHeal(
                                stage: "dropUnsolicitedScheduleOverride",
                                callNames: CoachCatalogToolName.scheduleAdjustment.rawValue,
                                userText: text
                            )
                        }
                    }
                }
            }

            if case .workoutStart = pendingAction?.kind,
               !CoachChatIntent.shouldKeepWorkoutStart(text, lastAssistant: lastAssistant) {
                let callNames = assembledTurn.functionCalls.map(\.name).joined(separator: ",")
                await logCoachHeal(
                    stage: "dropUnmatchedWorkoutStart",
                    callNames: callNames.isEmpty ? "workout_start" : callNames,
                    userText: text
                )
                pendingAction = nil
                assembledTurn.functionCalls.removeAll {
                    $0.name == CoachCatalogToolName.workoutStart.rawValue
                }
            }

            if CoachChatIntent.shouldDropUnsolicitedDeloadPitch(text) {
                let pitched = assembledTurn.text.lowercased()
                if pitched.contains("deload") || pitched.contains("confirm to start") {
                    assembledTurn.text = "Hello."
                    pendingAction = nil
                }
            }

            let visibleAfterGate = CoachChatTextFormatter.userFacingText(from: assembledTurn.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !didProseHeal,
               coachUserMessage == nil,
               !wasFoodDictation,
               visibleAfterGate.isEmpty,
               pendingAction == nil,
               pendingFoodMealConfirm == nil,
               assembledTurn.functionCalls.isEmpty {
                await logCoachHeal(stage: "proseOnlyAfterDroppedWrite", callNames: "none", userText: text)
                didProseHeal = true
                let healed = try await streamAssistantTurn(
                    provider: provider,
                    systemInstructions: prompt.systemInstructions,
                    contextBlock: prompt.contextBlock,
                    userMessage: Self.proseOnlyNudge(providerUserMessage),
                    thread: thread,
                    allowEmptyRetry: false,
                    freshnessSuffix: prompt.freshnessSuffix
                )
                let healedVisible = CoachChatTextFormatter.userFacingText(from: healed.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !healedVisible.isEmpty || !healed.functionCalls.isEmpty {
                    assembledTurn = healed
                    pendingAction = CoachChatActionParser.proposal(
                        from: healed.text,
                        functionCalls: healed.functionCalls
                    )
                    if case .workoutStart = pendingAction?.kind,
                       !CoachChatIntent.shouldKeepWorkoutStart(text, lastAssistant: lastAssistant) {
                        pendingAction = nil
                        assembledTurn.functionCalls.removeAll {
                            $0.name == CoachCatalogToolName.workoutStart.rawValue
                        }
                    }
                    if CoachChatIntent.suppressesWriteProposals(text) {
                        pendingAction = nil
                    }
                }
            }

            // Start affirmatives need a real confirm card, not prose "Confirm to start?" (CAM-111).
            if forceWorkoutStartCard,
               !isPendingWorkoutStart(pendingAction),
               CoachChatIntent.isProseOnlyWorkoutStartConfirm(assembledTurn.text)
            {
                assembledTurn.text =
                    "I still need a Start workout card. Ask me to list the session again, then say Go."
                assembledTurn.functionCalls.removeAll {
                    $0.name == CoachCatalogToolName.workoutStart.rawValue
                }
            }

            var storedText = CoachChatTextFormatter.userFacingText(from: assembledTurn.text)
            let chart = chartPayload(from: assembledTurn, original: querySource)
            if let chart {
                storedText = CoachChatChartStitcher.appending(chart, to: storedText)
            }
            let userFacingText = CoachChatDisplayText.assistantText(
                from: storedText,
                pendingAction: pendingAction
            )
            let hasChart = chart != nil || ChartPayloadParser.parse(from: storedText) != nil
            let navigate = navigatePayload(from: assembledTurn, original: querySource)
                ?? CoachChatIntent.inferredNavigateTab(from: text).map { NavigatePayload(tab: $0) }

            guard !userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || pendingAction != nil
                || pendingFoodMealConfirm != nil
                || hasChart
                || navigate != nil
            else {
                await logEmptyAssembledTurn(
                    stage: "strippedEmpty",
                    attempt: 0,
                    turn: assembledTurn,
                    extra: [
                        "rawChars": String(assembledTurn.text.count),
                        "visibleChars": String(userFacingText.count),
                        "hasPendingAction": pendingAction == nil ? "0" : "1",
                        "hasChart": hasChart ? "1" : "0",
                        "hasNavigate": navigate == nil ? "0" : "1"
                    ]
                )
                throw CoachStructuredOutputError.emptyResponse
            }

            // Persist an assistant row whenever we have visible text, a chart, or a confirm card.
            // Confirm cards must anchor to a message id (CAM-86).
            var assistantMessageID: String?
            if !userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasChart {
                let assistantMessage = try persistence.chat.append(
                    ChatMessageInsert(
                        role: .assistant,
                        text: hasChart ? storedText : userFacingText,
                        promptVersion: CoachPromptVersion.chatV1.rawValue,
                        schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                    )
                )
                messages.append(assistantMessage)
                assistantMessageID = assistantMessage.id
                trimVisibleChatHistory()
            } else if pendingAction != nil {
                let spoken = CoachChatDisplayText.assistantText(from: "", pendingAction: pendingAction)
                let assistantMessage = try persistence.chat.append(
                    ChatMessageInsert(
                        role: .assistant,
                        text: spoken,
                        promptVersion: CoachPromptVersion.chatV1.rawValue,
                        schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                    )
                )
                messages.append(assistantMessage)
                assistantMessageID = assistantMessage.id
                trimVisibleChatHistory()
            } else if navigate != nil, pendingFoodMealConfirm == nil {
                let note = "Opened \(navigate!.tab)."
                let assistantMessage = try persistence.chat.append(
                    ChatMessageInsert(
                        role: .assistant,
                        text: note,
                        promptVersion: CoachPromptVersion.chatV1.rawValue,
                        schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                    )
                )
                messages.append(assistantMessage)
                trimVisibleChatHistory()
            }

            if let pendingAction, let assistantMessageID {
                setPendingChatAction(pendingAction, anchoredTo: assistantMessageID)
            } else if pendingAction == nil,
                      let assistantMessageID,
                      let labels = CoachChatIntent.structuredPromptLabels(from: userFacingText) {
                attachStructuredPrompt(
                    messageID: assistantMessageID,
                    question: userFacingText,
                    confirmLabel: labels.confirm,
                    cancelLabel: labels.cancel
                )
            }

            presentOrDeferNavigate(navigate)
            lastFailedUserMessage = nil
            CoachDiagnosticsStore.shared.clearTurnState()
            finishStreamingPresentation()
            clearChatProgress()

            maybeTriggerMemoryRefinementExtraction(profile: profile)

            if pendingAction == nil,
               CoachChatActionParser.hasMalformedFoodLogCall(assembledTurn.functionCalls)
                || FoodLogPayloadParser.hasMalformedBlock(in: assembledTurn.text) {
                lastTurnError = "Couldn't read that meal log. Ask again with calories."
            } else if lastTurnError == nil,
                      pendingFoodMealConfirm == nil,
                      forceWorkoutStartCard,
                      !isPendingWorkoutStart(pendingAction) {
                lastTurnError = "Couldn't start that workout. Say Go again after I show the Start workout card."
            } else if wasFoodDictation, pendingFoodMealConfirm == nil, lastTurnError == nil {
                // Nutrition describe has no chat transcript UI - prose-only replies looked like a hang.
                lastTurnError = "Couldn't estimate that meal. Try again with clearer portions, or use Search."
            } else if !wasFoodDictation,
                      pendingAction == nil,
                      pendingFoodMealConfirm == nil,
                      lastTurnError == nil,
                      CoachChatIntent.looksLikeFoodLog(text),
                      !hasDecodableFoodLog(in: assembledTurn) {
                lastTurnError = "Couldn't log that meal. Try again with the food name and approximate calories."
            }

            await logTurn(
                status: "completed",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue,
                messageCount: messages.count
            )
        } catch is CancellationError {
            isFoodDictationTurn = false
            clearChatProgress()
            isPreparingFoodMealConfirm = false
            isStreaming = false
            streamingText = nil
            CoachDiagnosticsStore.shared.clearTurnState()
            degradedState = CoachFailurePolicy.degradedState(for: CancellationError())
            await logTurn(
                status: "cancelled",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                messageCount: messages.count
            )
        } catch {
            if await persistGroundedChartIfPossible(userText: text) {
                isFoodDictationTurn = false
                clearChatProgress()
                isPreparingFoodMealConfirm = false
                isStreaming = false
                streamingText = nil
                lastFailedUserMessage = nil
                lastTurnError = nil
                return
            }
            isFoodDictationTurn = false
            clearChatProgress()
            isPreparingFoodMealConfirm = false
            isStreaming = false
            streamingText = nil
            CoachDiagnosticsStore.shared.clearTurnState()
            degradedState = CoachFailurePolicy.degradedState(for: error)
            lastTurnError = CoachUserFacingError.message(for: error)
            CoachDiagnosticsStore.shared.recordFailure(surface: "chat", error: error)
            let nsError = error as NSError
            await DiagnosticsLog.shared.capture(
                error: error,
                category: .coachLLM,
                message: "Chat turn failed",
                context: [
                    "domain": nsError.domain,
                    "code": String(nsError.code),
                    "detail": String(error.localizedDescription.prefix(240))
                ]
            )
            await logTurn(
                status: "failed",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                messageCount: messages.count,
                error: error
            )
        }
    }

    private func persistGroundedChartIfPossible(userText: String) async -> Bool {
        guard let kind = CoachChatIntent.inferredChartKind(from: userText) else { return false }
        let endDay = HelmDay.day(for: .now, calendar: .current)
        guard let chart = try? CoachChatChartBuilder.build(
            kind: kind,
            store: persistence,
            endingAt: endDay
        ) else {
            return false
        }
        let persistText = ChartPayloadParser.persistText(reply: chart.reply, payload: chart)
        do {
            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: persistText,
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.chartV1.rawValue
                )
            )
            messages.append(assistantMessage)
            trimVisibleChatHistory()
            CoachDiagnosticsStore.shared.clearTurnState()
            await logTurn(
                status: "completed",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                schemaVersion: CoachOutputSchemaVersion.chartV1.rawValue,
                messageCount: messages.count
            )
            return true
        } catch {
            return false
        }
    }

    private func navigateIfRequested(from text: String) {
        if CoachChatIntent.looksLikeOpenTrain(text) {
            AppTabRouter.shared.openTrain()
            return
        }
        guard CoachChatIntent.looksLikeOpenNutrition(text) else { return }
        let calendar = Calendar.current
        let now = Date()
        let today = HelmDay.day(for: now, calendar: calendar)
        let namedDay = CoachChatIntent.inferredHelmDay(from: text, now: now, calendar: calendar)
        let searchDays = namedDay.map { [$0] } ?? [today, today.adding(days: -1, calendar: calendar)]
        var meals: [MealRecord] = []
        for day in searchDays {
            meals.append(contentsOf: (try? persistence.nutrition.fetchMeals(for: day)) ?? [])
        }
        let match = preferredMeal(forNavigation: text, meals: meals)
        let day = match?.helmDay ?? namedDay ?? today
        AppTabRouter.shared.openNutrition(
            focus: NutritionNavigationFocus(helmDay: day, mealID: match?.id)
        )
    }

    private func preferredMeal(forNavigation text: String, meals: [MealRecord]) -> MealRecord? {
        let lower = text.lowercased()
        var result = meals
        if lower.contains("snack") {
            result = result.filter { $0.bucket == .snacks }
        } else if lower.contains("lunch") {
            result = result.filter { $0.bucket == .lunch }
        } else if lower.contains("breakfast") {
            result = result.filter { $0.bucket == .breakfast }
        } else if lower.contains("dinner") {
            result = result.filter { $0.bucket == .dinner }
        }
        let stop: Set<String> = [
            "open", "the", "entry", "of", "just", "locked", "logged", "navigate",
            "nutrition", "yesterday", "today", "please", "show", "take"
        ]
        let tokens = lower
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 4 && !stop.contains($0) }
        if let token = tokens.first {
            let named = result.filter { $0.name.lowercased().contains(token) }
            if !named.isEmpty {
                result = named
            }
        }
        return result.max(by: { $0.loggedAt < $1.loggedAt })
    }

    private func makeCoachPrompt(
        profile: MemoryProfile,
        days: CoachContextDays,
        budget: Int,
        turn: ContextTurn
    ) -> CoachPrompt {
        ContextBuilder.build(
            profile: profile,
            days: days,
            budget: budget,
            turn: turn,
            appSurface: currentAppSurface(),
            calendarDay: HelmDay.day(for: .now, calendar: .current)
        )
    }

    private func currentAppSurface() -> CoachAppSurfaceSnapshot {
        let now = Date()
        let today = HelmDay.day(for: now, calendar: .current)
        let session = try? persistence.activeSessions.fetchActiveSnapshot(at: now)
        let sessionDay = session.map { HelmDay.day(for: $0.session.startedAt, calendar: .current) }
        let stale = sessionDay.map { $0 != today } ?? false
        return CoachAppSurfaceSnapshot(
            selectedTab: AppTabRouter.shared.selectedTab.coachSurfaceLabel,
            sessionStatus: session?.session.status.rawValue ?? "none",
            sessionTitle: session?.session.title,
            viewedNutritionDay: AppTabRouter.shared.selectedTab == .nutrition
                ? NutritionBootstrap.lastViewedHelmDay?.formatted
                : nil,
            sessionHelmDay: sessionDay?.formatted,
            sessionStale: stale
        )
    }

    private struct AssembledCoachTurn {
        var text: String
        var functionCalls: [CoachLLMFunctionCall]

        var isEmpty: Bool {
            CoachChatTextFormatter.userFacingText(from: text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty && functionCalls.isEmpty
        }
    }

    private func keepIfFollowUpEmpty(
        _ current: AssembledCoachTurn,
        next: AssembledCoachTurn
    ) -> AssembledCoachTurn {
        let nextVisible = CoachChatTextFormatter.userFacingText(from: next.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if nextVisible.isEmpty {
            return current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? next : current
        }
        return next
    }

    private func followUpOrKeepCurrent(
        _ current: AssembledCoachTurn,
        next: () async throws -> AssembledCoachTurn
    ) async throws -> AssembledCoachTurn {
        do {
            return keepIfFollowUpEmpty(current, next: try await next())
        } catch let error as CoachStructuredOutputError where error == .emptyResponse {
            let visible = CoachChatTextFormatter.userFacingText(from: current.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if visible.isEmpty { throw error }
            return current
        }
    }

    /// Meal lookup follow-up: on provider/empty failure, keep DB summary so the turn does not blank (CAM-84).
    private func mealQueryFollowUpOrFallback(
        current: AssembledCoachTurn,
        query: MealQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay
    ) async -> AssembledCoachTurn {
        do {
            let results = try MealHistoryQueryService(store: persistence).run(query)
            lastMealQueryContext = MealQueryContext.from(query: query, results: results)
            do {
                let followUp = try await runMealQueryFollowUp(
                    query: query,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: current.text,
                    prefetchedResults: results
                )
                return keepIfFollowUpEmpty(current, next: followUp)
            } catch {
                let fallback = mealQueryFallbackText(results: results, priorText: current.text)
                return AssembledCoachTurn(text: fallback, functionCalls: [])
            }
        } catch {
            let visible = CoachChatTextFormatter.userFacingText(from: current.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty { return current }
            return AssembledCoachTurn(
                text: "I couldn't look up that meal history right now. Try again in a moment.",
                functionCalls: []
            )
        }
    }

    private func mealQueryFallbackText(results: String, priorText: String) -> String {
        let prior = CoachChatTextFormatter.userFacingText(from: priorText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = results.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            return prior.isEmpty
                ? "I couldn't find that meal history."
                : prior
        }
        if prior.isEmpty {
            return "Here's what I found:\n\(summary)"
        }
        return "\(prior)\n\nHere's what I found:\n\(summary)"
    }

    private func hasDecodableFoodLog(in turn: AssembledCoachTurn) -> Bool {
        CoachChatActionParser.foodLogPayload(from: turn.functionCalls) != nil
            || FoodLogPayloadParser.parse(from: turn.text) != nil
    }

    private func catalogQuery<Payload>(
        named name: CoachCatalogToolName,
        from turn: AssembledCoachTurn,
        userText: String,
        decode: ([CoachLLMFunctionCall]) -> Payload?,
        parseJSON: (String) -> Payload?,
        infer: (String) -> Payload?
    ) -> Payload? {
        CoachCatalogQueryResolver.resolve(
            named: name,
            functionCalls: turn.functionCalls,
            assembledText: turn.text,
            userText: userText,
            decode: decode,
            parseJSON: parseJSON,
            infer: infer
        )
    }

    private func chartPayload(
        from current: AssembledCoachTurn,
        original: AssembledCoachTurn
    ) -> ChartPayload? {
        CoachCatalogQueryResolver.mergeNonQueryPayload(
            currentCalls: current.functionCalls,
            originalCalls: original.functionCalls,
            currentText: current.text,
            originalText: original.text,
            decode: CoachCatalogQueryDecoder.chart,
            parseJSON: ChartPayloadParser.parse
        )
    }

    private func navigatePayload(
        from current: AssembledCoachTurn,
        original: AssembledCoachTurn
    ) -> NavigatePayload? {
        CoachCatalogQueryResolver.mergeNonQueryPayload(
            currentCalls: current.functionCalls,
            originalCalls: original.functionCalls,
            currentText: current.text,
            originalText: original.text,
            decode: CoachCatalogQueryDecoder.navigate,
            parseJSON: NavigatePayloadParser.parse
        )
    }

    private func presentOrDeferNavigate(_ payload: NavigatePayload?) {
        pendingNavigateTab = nil
        switch CoachNavigatePresentation.resolve(
            tab: payload?.tab,
            hasPendingConfirm: pendingChatAction != nil || pendingFoodMealConfirm != nil
        ) {
        case let .now(label):
            if let tab = AppTab(coachSurfaceLabel: label) {
                AppTabRouter.shared.open(tab)
            }
        case let .afterConfirm(label):
            pendingNavigateTab = AppTab(coachSurfaceLabel: label)
        case .none:
            break
        }
    }

    private func applyDeferredNavigateIfNeeded() {
        guard let tab = pendingNavigateTab else { return }
        pendingNavigateTab = nil
        AppTabRouter.shared.open(tab)
    }

    private func streamAssistantTurn(
        provider: any CoachLLMProvider,
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        allowEmptyRetry: Bool,
        freshnessSuffix: String? = nil
    ) async throws -> AssembledCoachTurn {
        for attempt in 0 ... (allowEmptyRetry ? 1 : 0) {
            isStreaming = true
            streamingText = attempt == 0 ? (streamingText ?? "") : "Retrying…"
            var assembled = ""
            var functionCalls: [CoachLLMFunctionCall] = []
            do {
                let events = try await provider.respondTurn(
                    systemInstructions: systemInstructions,
                    contextBlock: contextBlock,
                    userMessage: userMessage,
                    thread: thread,
                    freshnessSuffix: freshnessSuffix
                )
                for try await event in events {
                    try Task.checkCancellation()
                    switch event {
                    case .text(let chunk):
                        assembled += chunk
                        publishStreamingText(assembled)
                    case .functionCall(let call):
                        functionCalls.append(call)
                    }
                }
                flushPendingStreamingText()
            } catch is CancellationError {
                finishStreamingPresentation()
                throw CancellationError()
            }
            let turn = AssembledCoachTurn(text: assembled, functionCalls: functionCalls)
            if !turn.isEmpty {
                return turn
            }
            await logEmptyAssembledTurn(
                stage: attempt == 0 && allowEmptyRetry ? "streamEmptyRetrying" : "streamEmptyFinal",
                attempt: attempt,
                turn: turn
            )
            if attempt == 0, allowEmptyRetry {
                continue
            }
            throw CoachStructuredOutputError.emptyResponse
        }
        throw CoachStructuredOutputError.emptyResponse
    }


    private static func proseOnlyNudge(_ userMessage: String) -> String {
        """
        \(userMessage)

        [System: The previous attempt failed or called a write tool the athlete did not ask for. Answer in visible prose only. Do not call workout_start or any other write tool.]
        """
    }

    private func logCoachHeal(stage: String, callNames: String, userText: String) async {
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: .error,
            message: "Chat turn heal",
            context: [
                "stage": stage,
                "callNames": callNames,
                "looksLikeWorkoutStart": CoachChatIntent.looksLikeWorkoutStart(userText) ? "1" : "0",
                "suppressesWrite": CoachChatIntent.suppressesWriteProposals(userText) ? "1" : "0",
                "textLength": String(userText.count)
            ]
        )
    }

    private func logEmptyAssembledTurn(
        stage: String,
        attempt: Int,
        turn: AssembledCoachTurn,
        extra: [String: String] = [:]
    ) async {
        let visible = CoachChatTextFormatter.userFacingText(from: turn.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let callNames = turn.functionCalls.prefix(6).map(\.name).joined(separator: ",")
        var context: [String: String] = [
            "stage": stage,
            "attempt": String(attempt),
            "rawChars": String(turn.text.count),
            "visibleChars": String(visible.count),
            "callCount": String(turn.functionCalls.count),
            "callNames": callNames.isEmpty ? "none" : callNames
        ]
        for (key, value) in extra {
            context[key] = value
        }
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: .error,
            message: "Chat turn empty",
            context: context
        )
    }

    private func needsStructuredWorkoutStart(
        assembled: String,
        functionCalls: [CoachLLMFunctionCall],
        userText: String
    ) -> Bool {
        if let fromTool = CoachChatActionParser.workoutStartPayload(from: functionCalls) {
            return needsStructuredWorkoutStart(payload: fromTool, userText: userText)
        }
        guard let payload = WorkoutStartPayloadParser.parse(from: assembled) else {
            return true
        }
        return needsStructuredWorkoutStart(payload: payload, userText: userText)
    }

    private func needsStructuredWorkoutStart(payload: WorkoutStartPayload, userText: String) -> Bool {
        let emptyExercises = payload.exercises == nil || payload.exercises?.isEmpty == true
        if emptyExercises, payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV1.rawValue {
            // Bare engine start is OK only when the athlete did not negotiate a custom list.
            return CoachChatIntent.looksLikeWorkoutProposal(userText)
                || messages.suffix(8).contains {
                    $0.role == .user && CoachChatIntent.looksLikeWorkoutProposal($0.text)
                }
        }
        if emptyExercises {
            return true
        }
        return false
    }

    private func runStructuredWorkoutStart(
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        contextDays: CoachContextDays,
        thread: CoachThreadState,
        userText: String,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )
        let toolMessage = """
        # Workout start (structured)
        Athlete is ready to start. Recent workouts and training plan are in context.
        Prior coach draft:
        \(CoachChatTextFormatter.userFacingText(from: priorAssembled))

        Return workout_start.v2 JSON with reply plus every agreed exercise and sets. Do not ask for verbal confirmation.
        Athlete message: \(userText)
        """
        isStreaming = true
        streamingText = "Building workout start…"
        let artefact = try await provider.generateWorkoutStart(
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread
        )
        guard !artefact.payload.exercises.isEmpty else {
            throw CoachWorkoutStartAdjuster.StartError.emptySession
        }
        return AssembledCoachTurn(
            text: try artefact.payload.chatAssemblyText(),
            functionCalls: []
        )
    }

    private func runWorkoutQueryFollowUp(
        query: WorkoutQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = WorkoutHistoryQueryService(store: persistence)
        let results = try service.run(query)
        let toolMessage = """
        # Workout query results
        \(results)

        Review the session for the athlete in chat-length prose. Do not invent sets that are not listed. Do not dump a raw metric list.
        """

        isStreaming = true
        streamingText = "Looking up workouts…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runRecoveryQueryFollowUp(
        query: RecoveryQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String,
        cachedContextDays: CoachContextDays
    ) async throws -> AssembledCoachTurn {
        let service = RecoveryHistoryQueryService(store: persistence)
        let results = try await service.run(query)
        let toolMessage = """
        # Recovery query results
        \(results)

        Answer using these numbers. Prefer HRV and hrvVsChronic when explaining recovery. Do not invent metrics that are not listed. Do not dump a raw metric list.
        """

        isStreaming = true
        streamingText = "Looking up recovery…"

        _ = endDay
        let contextDays = cachedContextDays
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runCalendarQueryFollowUp(
        query: CalendarQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = CalendarHistoryQueryService()
        let results = await service.run(query)
        let toolMessage = """
        # Calendar query results
        \(results)

        Answer from these EventKit results. List real event titles, locations, and times. If the query header includes search=, only those matches matter: give dates and duration. lookahead=N is the search window in days; if the athlete asked how long the window is, answer N. If events=none for a search, say that title was not found in the next N days. If engine_busy=true, explain the reason line (all-day, scheduled-hours threshold, or event-count threshold). If engine_busy=false, say the day is below the busy thresholds even if some events exist. Never invent events. If calendar_status is not authorized, tell the athlete to enable calendar access in Settings.
        """

        isStreaming = true
        streamingText = "Looking up calendar…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        do {
            let streamed = try await streamAssistantTurn(
                provider: provider,
                systemInstructions: prompt.systemInstructions,
                contextBlock: prompt.contextBlock,
                userMessage: toolMessage,
                thread: thread,
                allowEmptyRetry: false,
                freshnessSuffix: prompt.freshnessSuffix
            )
            if streamed.isEmpty {
                return AssembledCoachTurn(text: calendarSyncFallback(results), functionCalls: [])
            }
            return streamed
        } catch {
            if error is CancellationError { throw error }
            return AssembledCoachTurn(text: calendarSyncFallback(results), functionCalls: [])
        }
    }

    private func calendarSyncFallback(_ results: String) -> String {
        let summary = results.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty {
            return "Calendar sync finished. I couldn't read any events from that window."
        }
        return "Calendar sync finished.\n\(summary)"
    }

    private func runTrendsQueryFollowUp(
        query: TrendsQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        var healthFacts = ""
        if query.queryType == .bodyFat {
            isStreaming = true
            streamingText = "Checking Apple Health for body fat…"
            _ = await HealthKitBootstrap.healthKitIngest.syncKinds([.bodyFatPercentage])
            _ = await HealthKitBootstrap.healthKitIngest.liveBodyFatSummary()
            let trace = await HealthKitBootstrap.healthKitIngest.lastBodyFatQueryTrace()
            let facts = await HealthKitBootstrap.healthKitIngest.lastBodyFatLatestFacts()
            var context = trace.diagnosticContext
            context["hkHasReading"] = facts.hkPercent == nil ? "false" : "true"
            context["storeHasReading"] = facts.storePercent == nil ? "false" : "true"
            if let source = facts.hkSource {
                context["hkSource"] = source
            }
            context["reply"] = "model"
            await DiagnosticsLog.shared.record(
                category: .coachLLM,
                level: facts.hkPercent == nil ? .error : .info,
                message: "Coach body fat follow-up",
                context: context
            )
            healthFacts = facts.trendToolLines() + "\n"
        }
        let service = TrendsHistoryQueryService(store: persistence)
        let results = try service.run(query)
        let toolMessage = """
        # Trends query results
        \(healthFacts)\(results)

        Answer the athlete's latest message in chat-length style grounded in the numbers. If they asked for a trend, use the history rows (up, down, or stable) and what might be driving it. Do not reply with only the newest sample when they asked for a trend or something else. Not a raw metric dump.
        """

        isStreaming = true
        streamingText = "Looking up trends…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runPatternQueryFollowUp(
        query: PatternQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = PatternQueryService(store: persistence)
        let results = try service.run(query)
        let toolMessage = """
        # Pattern query results
        \(results)

        Narrate only these stored PatternKit cards. Association language, not causal. \
        If findings=none or n is too small, say so. Never invent a correlation or dump raw day logs.
        """

        isStreaming = true
        streamingText = "Looking up patterns…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runNutritionQueryFollowUp(
        query: NutritionQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = NutritionQueryService(store: persistence)
        let results = try await service.run(query)
        let toolMessage = """
        # Nutrition query results
        \(results)

        Answer the athlete from these exact engine numbers. These are authoritative. Never recompute TDEE, trend weight, targets, or budget. Quote them directly. If the weekly budget is present, explain how the remaining calories are distributed across the week and which days are heavier or lighter. Never invent data.
        """

        isStreaming = true
        streamingText = "Looking up nutrition…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runContextRefreshFollowUp(
        payload: ContextRefreshPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String,
        cachedContextDays: CoachContextDays
    ) async throws -> AssembledCoachTurn {
        let labels = payload.blocks.joined(separator: ", ")
        let toolMessage = """
        # Context refresh
        Rebuilt: \(labels). Use the context block. Do not invent data. Do not request another context_refresh unless still stale.
        """

        isStreaming = true
        streamingText = "Refreshing context…"

        _ = endDay
        let contextDays = cachedContextDays
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runHealthSyncFollowUp(
        payload: HealthSyncPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        _ = payload
        isStreaming = true
        streamingText = "Syncing Health…"

        let outcome = await HealthKitBootstrap.healthKitIngest.syncKinds([
            .hrvSDNN, .restingHeartRate, .sleep, .respiratoryRate, .wristTemperature, .bodyMass
        ])
        await ReadinessBootstrap.readinessService.refresh()
        let status = await HealthKitBootstrap.healthKitIngest.currentStatus()
        let today = HelmDay.day(for: Date(), calendar: .current)
        let metrics = try? persistence.dailyMetrics.fetch(helmDay: today)
        let syncAt = status.lastSyncFinishedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        let hrv = metrics?.hrvSDNN.map { "\($0.milliseconds)ms" } ?? "none"
        let rhr = metrics?.restingHeartRate.map { "\($0) bpm" } ?? "none"
        let bodyMass = try? persistence.bodyComposition
            .fetchLatest(onOrBefore: today, limit: 1)
            .first?
            .mass
            .kilograms
        let bodyMassLabel = bodyMass.map { String(format: "%.1f kg", $0) } ?? "none"
        let results = """
        synced_at=\(syncAt)
        samples_ingested=\(outcome.samplesIngested)
        samples_deleted=\(outcome.samplesDeleted)
        hrv_sdnn=\(hrv)
        resting_hr=\(rhr)
        body_mass=\(bodyMassLabel)
        """
        let fallback = "HealthKit sync finished at \(syncAt). HRV \(hrv), resting HR \(rhr), body mass \(bodyMassLabel)."
        let toolMessage = """
        # Health sync results
        \(results)

        Answer using these timestamps and numbers. Do not invent metrics. If samples_ingested is 0, say Health had nothing new.
        """

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        do {
            let streamed = try await streamAssistantTurn(
                provider: provider,
                systemInstructions: prompt.systemInstructions,
                contextBlock: prompt.contextBlock,
                userMessage: toolMessage,
                thread: thread,
                allowEmptyRetry: false,
                freshnessSuffix: prompt.freshnessSuffix
            )
            if streamed.isEmpty {
                return AssembledCoachTurn(text: fallback, functionCalls: [])
            }
            return streamed
        } catch {
            if error is CancellationError { throw error }
            return AssembledCoachTurn(text: fallback, functionCalls: [])
        }
    }

    private func runMealQueryFollowUp(
        query: MealQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String,
        prefetchedResults: String? = nil
    ) async throws -> AssembledCoachTurn {
        let results: String
        if let prefetchedResults {
            results = prefetchedResults
        } else {
            results = try MealHistoryQueryService(store: persistence).run(query)
            lastMealQueryContext = MealQueryContext.from(query: query, results: results)
        }
        let toolMessage = """
        # Meal query results
        \(results)

        Answer the athlete using these results. If they asked to copy a meal, call the meal_copy tool. Do not invent foods not listed.
        """

        isStreaming = true
        streamingText = "Looking up meals…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = makeCoachPrompt(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: false,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func resolvedFoodLogBucket(_ raw: String?) -> MealBucket {
        guard let raw else { return .snacks }
        let normalized = raw.lowercased()
        if normalized == "snack" { return .snacks }
        return MealBucket(rawValue: normalized) ?? .snacks
    }

    private func beginFoodDictationProgress(step: String) {
        chatProgressTitle = "Voice meal log"
        chatProgressCompletedSteps = []
        chatProgressStep = step
        isPreparingFoodMealConfirm = false
    }

    private func finishStreamingPresentation() {
        isStreaming = false
        pendingStreamingText = nil
        streamingText = nil
    }

    private func publishStreamingText(_ text: String) {
        pendingStreamingText = text
        let now = Date()
        guard now.timeIntervalSince(lastStreamingUIPublish) >= Self.streamingUIInterval else {
            return
        }
        lastStreamingUIPublish = now
        streamingText = text
    }

    private func flushPendingStreamingText() {
        guard let pending = pendingStreamingText else { return }
        pendingStreamingText = nil
        lastStreamingUIPublish = Date()
        streamingText = pending
    }

    private func clearChatProgress() {
        chatProgressTitle = nil
        chatProgressCompletedSteps = []
        chatProgressStep = nil
        isPreparingFoodMealConfirm = false
    }

    private func trimVisibleChatHistory() {
        let limit = ChatStore.chatUILimit
        guard messages.count > limit else { return }
        messages = Array(messages.suffix(limit))
    }

    /// Triggered when the thread exceeds 20 messages and at least 5 turns
    /// have elapsed since the last compaction. Compresses old messages into
    /// a ThreadContextSummary, preserving the last 10 verbatim.
    private func compactThread(
        _ thread: CoachThreadState,
        provider: any CoachLLMProvider
    ) async throws -> CoachThreadState {
        let allMessages = thread.messages
        let keepCount = 10
        guard allMessages.count > keepCount else { return thread }

        let oldMessages = Array(allMessages.prefix(allMessages.count - keepCount))
        let recentMessages = Array(allMessages.suffix(keepCount))

        // Build a compact conversation transcript for the summariser.
        var transcriptLines: [String] = []
        // Include the previous summary as context if it exists.
        if let prevSummary = thread.summary, !prevSummary.isEmpty {
            transcriptLines.append("[Previous Thread Context]")
            transcriptLines.append(prevSummary.promptBlock)
            transcriptLines.append("")
        }
        for msg in oldMessages {
            let role = msg.role == .user ? "Athlete" : "Coach"
            transcriptLines.append("\(role): \(msg.text)")
        }
        let conversationText = transcriptLines.joined(separator: "\n")

        do {
            var fullResponse = ""
            let stream = try await provider.respond(
                systemInstructions: ThreadContextSummary.summarisationPrompt,
                contextBlock: "",
                userMessage: conversationText,
                thread: CoachThreadState.empty,
                freshnessSuffix: nil
            )
            for try await chunk in stream {
                fullResponse += chunk
            }

            let raw = fullResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = parseSummary(from: raw, compressedCount: oldMessages.count)

            return CoachThreadState(messages: recentMessages, summary: summary)
        } catch {
            // If summarisation fails, keep the thread intact.
            return thread
        }
    }

    /// Parses summarisation output into a ThreadContextSummary.
    private func parseSummary(from text: String, compressedCount: Int) -> ThreadContextSummary {
        let summary = ThreadContextSummary(
            decisions: extractSection("# Decisions Made", from: text),
            openQuestions: extractSection("# Open Questions", from: text),
            coachCommitments: extractSection("# Coach Commitments", from: text),
            athleteState: extractSection("# Athlete State", from: text),
            activeNegotiations: extractSection("# Active Negotiations", from: text),
            nutritionContext: extractSection("# Nutrition Context", from: text),
            compressedMessageCount: compressedCount
        )
        return summary
    }

    /// Extracts content between one section header and the next, or end of text.
    private func extractSection(_ header: String, from text: String) -> String {
        let allHeaders = [
            "# Decisions Made", "# Open Questions", "# Coach Commitments",
            "# Athlete State", "# Active Negotiations", "# Nutrition Context"
        ]
        guard let startRange = text.range(of: header) else { return "" }
        let start = startRange.upperBound
        let remainder = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)

        var end = remainder.endIndex
        for h in allHeaders where h != header {
            if let r = remainder.range(of: h) {
                end = remainder.index(r.lowerBound, offsetBy: 0)
                break
            }
        }
        return String(remainder[..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// if the session warrants it (>= 3 substantive user turns, >= 30 min since last).
    private func completeSessionCoachTurn(
        text: String,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        contextDays: CoachContextDays,
        thread: CoachThreadState
    ) async throws {
        isStreaming = true
        streamingText = ""
        chatProgressStep = "Checking today's session…"
        defer {
            finishStreamingPresentation()
            clearChatProgress()
        }

        let sessionProposal = try await TrainBootstrap.sessionController.proposeChatSessionAdjustment(
            userMessage: text,
            provider: provider,
            profile: profile,
            context: contextDays,
            thread: thread
        )
        let pendingAction = CoachChatActionParser.proposal(fromSession: sessionProposal)
        var storedText = sessionProposal.displayedAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        if storedText.isEmpty, let pendingAction {
            storedText = CoachChatDisplayText.assistantText(from: "", pendingAction: pendingAction)
        }
        guard !storedText.isEmpty || pendingAction != nil else {
            throw CoachStructuredOutputError.emptyResponse
        }

        lastFailedUserMessage = nil
        CoachDiagnosticsStore.shared.clearTurnState()

        if !storedText.isEmpty {
            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: storedText,
                    promptVersion: CoachPromptVersion.sessionAdjustmentV2.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue
                )
            )
            messages.append(assistantMessage)
            trimVisibleChatHistory()
            if let pendingAction {
                setPendingChatAction(pendingAction, anchoredTo: assistantMessage.id)
            }
        } else if let pendingAction {
            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: pendingAction.title,
                    promptVersion: CoachPromptVersion.sessionAdjustmentV2.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue
                )
            )
            messages.append(assistantMessage)
            trimVisibleChatHistory()
            setPendingChatAction(pendingAction, anchoredTo: assistantMessage.id)
        }

        finishStreamingPresentation()
        clearChatProgress()

        maybeTriggerMemoryRefinementExtraction(profile: profile)
        await logTurn(
            status: "completed",
            promptVersion: CoachPromptVersion.sessionAdjustmentV2.rawValue,
            schemaVersion: CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue,
            messageCount: messages.count
        )
    }

    private func maybeTriggerMemoryRefinementExtraction(profile: MemoryProfile) {
        guard pendingChatAction == nil, pendingFoodMealConfirm == nil else { return }

        let turns = messages.map {
            MemoryRefinementTrigger.Turn(
                isUser: $0.role == .user,
                text: $0.text,
                createdAt: $0.createdAt
            )
        }
        let lastExtraction = lastRefinementExtractionDate
            ?? UserDefaults.standard.object(forKey: Self.refinementExtractionDefaultsKey) as? Date
        guard MemoryRefinementTrigger.shouldExtract(
            messages: turns,
            lastExtraction: lastExtraction
        ) else { return }

        let window = MemoryRefinementTrigger.sessionWindow(from: turns)
        let sourceID = messages.last(where: { $0.role == .assistant })?.id
        let conversationText = window.map { turn in
            "\(turn.isUser ? "Athlete" : "Coach"): \(turn.text)"
        }.joined(separator: "\n\n")
        let profileContext = MemoryRefinementExtractor.profileContext(from: profile)

        Task(priority: .background) { [weak self] in
            guard let self else { return }
            let provider = await ProviderRegistry.shared.provider(
                for: self.providerPreferences.selectedProvider
            )
            do {
                var fullResponse = ""
                let stream = try await provider.respond(
                    systemInstructions: MemoryRefinementExtractor.extractionPrompt,
                    contextBlock: profileContext,
                    userMessage: conversationText,
                    thread: CoachThreadState.empty,
                    freshnessSuffix: nil
                )
                for try await chunk in stream {
                    fullResponse += chunk
                }
                guard let payload = MemoryRefinementExtractor.parse(fullResponse) else { return }
                await MainActor.run { [weak self] in
                    guard let self, !payload.refinements.isEmpty else { return }
                    if self.pendingChatAction != nil || self.pendingFoodMealConfirm != nil { return }
                    if let sourceID,
                       let sourceIndex = self.messages.firstIndex(where: { $0.id == sourceID })
                    {
                        let movedOn = self.messages[(sourceIndex + 1)...].contains { $0.role == .user }
                        if movedOn { return }
                    }
                    self.pendingMemoryRefinements = payload.refinements
                    self.memoryRefinementSourceMessageID = sourceID
                    self.markRefinementExtractionRan()
                }
            } catch {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "Memory refinement extraction failed",
                    context: ["detail": String(error.localizedDescription.prefix(240))]
                )
                await MainActor.run { [weak self] in
                    self?.markRefinementExtractionRan()
                }
            }
        }
    }

    private static let refinementExtractionDefaultsKey = "helm.chat.lastMemoryRefinementExtraction"

    private func markRefinementExtractionRan() {
        lastRefinementExtractionDate = .now
        UserDefaults.standard.set(lastRefinementExtractionDate, forKey: Self.refinementExtractionDefaultsKey)
    }

    private func logTurn(
        status: String,
        promptVersion: String,
        schemaVersion: String? = nil,
        messageCount: Int,
        error: Error? = nil
    ) async {
        var context: [String: String] = [
            "status": status,
            "promptVersion": promptVersion,
            "messageCount": String(messageCount)
        ]
        if let schemaVersion {
            context["schemaVersion"] = schemaVersion
        }
        if let error {
            let nsError = error as NSError
            context["error"] = "\(nsError.domain):\(nsError.code)"
            context["errorDetail"] = String(error.localizedDescription.prefix(240))
        }
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: error == nil ? .info : .error,
            message: "Chat turn \(status)",
            context: context
        )
    }

    private func reloadUndoableActions() {
        var map: [String: CoachAppliedAction] = [:]
        for message in messages where message.role == .assistant {
            if let action = try? persistence.coachAppliedActions.fetchUndoable(messageID: message.id) {
                map[message.id] = action
            }
        }
        undoableActionsByMessageID = map
    }

    private func reloadChatConfirmations() {
        let ids = messages.map(\.id)
        var records = (try? persistence.coachChatConfirmations.fetch(forMessageIDs: ids)) ?? []

        // Orphaned pending rows (no live proposal after relaunch) become skipped.
        for record in records where record.outcome == .pending {
            try? persistence.coachChatConfirmations.markResolved(
                messageID: record.messageID,
                outcome: .dismissed,
                selectedLabel: "Skipped"
            )
        }
        if records.contains(where: { $0.outcome == .pending }) {
            records = (try? persistence.coachChatConfirmations.fetch(forMessageIDs: ids)) ?? []
        }

        var map: [String: CoachChatConfirmation] = [:]
        for record in records {
            map[record.messageID] = record
        }
        chatConfirmationsByMessageID = map
        pendingChatActionMessageID = nil
    }

    private func attachStructuredPrompt(
        messageID: String,
        question: String,
        confirmLabel: String,
        cancelLabel: String
    ) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CoachChatConfirmation(
            messageID: messageID,
            title: confirmLabel == "Yes" ? "Yes or no" : "Your answer",
            detail: trimmed,
            reason: nil,
            confirmLabel: confirmLabel,
            cancelLabel: cancelLabel,
            outcome: .pending
        )
        structuredPromptMessageID = messageID
        chatConfirmationsByMessageID[messageID] = record
        try? persistence.coachChatConfirmations.upsert(record)
    }

    private func resolveStructuredPrompt(label: String) {
        guard let messageID = structuredPromptMessageID else { return }
        try? persistence.coachChatConfirmations.markResolved(
            messageID: messageID,
            outcome: .confirmed,
            selectedLabel: label
        )
        if var record = chatConfirmationsByMessageID[messageID] {
            record.outcome = .confirmed
            record.selectedLabel = label
            record.resolvedAt = .now
            chatConfirmationsByMessageID[messageID] = record
        }
        structuredPromptMessageID = nil
    }

    private func setPendingChatAction(
        _ proposal: CoachChatActionProposal,
        anchoredTo messageID: String
    ) {
        if pendingChatActionMessageID != nil, pendingChatActionMessageID != messageID {
            abandonPendingChatAction(selectedLabel: "Skipped", appendChoiceBubble: false)
        }
        pendingChatAction = proposal
        pendingChatActionMessageID = messageID
        let record = CoachChatConfirmation(
            messageID: messageID,
            title: proposal.title,
            detail: proposal.detail,
            reason: proposal.reason,
            confirmLabel: proposal.confirmLabel,
            cancelLabel: proposal.cancelLabel,
            outcome: .pending
        )
        chatConfirmationsByMessageID[messageID] = record
        try? persistence.coachChatConfirmations.upsert(record)
    }

    private func abandonPendingChatAction(
        selectedLabel: String,
        appendChoiceBubble: Bool = false
    ) {
        guard pendingChatAction != nil || pendingChatActionMessageID != nil else { return }
        if appendChoiceBubble {
            resolvePendingChatConfirmation(outcome: .dismissed, selectedLabel: selectedLabel)
        } else if let messageID = pendingChatActionMessageID {
            try? persistence.coachChatConfirmations.markResolved(
                messageID: messageID,
                outcome: .dismissed,
                selectedLabel: selectedLabel
            )
            if var record = chatConfirmationsByMessageID[messageID] {
                record.outcome = .dismissed
                record.selectedLabel = selectedLabel
                record.resolvedAt = .now
                chatConfirmationsByMessageID[messageID] = record
            }
        }
        pendingChatAction = nil
        pendingChatActionMessageID = nil
    }

    private func resolvePendingChatConfirmation(
        outcome: CoachChatConfirmation.Outcome,
        selectedLabel: String
    ) {
        guard let messageID = pendingChatActionMessageID else { return }
        try? persistence.coachChatConfirmations.markResolved(
            messageID: messageID,
            outcome: outcome,
            selectedLabel: selectedLabel
        )
        if var record = chatConfirmationsByMessageID[messageID] {
            record.outcome = outcome
            record.selectedLabel = selectedLabel
            record.resolvedAt = .now
            chatConfirmationsByMessageID[messageID] = record
        }
        appendConfirmationChoiceBubble(selectedLabel)
    }

    private func appendConfirmationChoiceBubble(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let userMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .user,
                    text: trimmed,
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                )
            )
            messages.append(userMessage)
            trimVisibleChatHistory()
        } catch {
            // Non-fatal: confirm/dismiss already applied.
        }
    }

    /// Verified ISO day + count after meal_copy / food_log delete so the model cannot claim the wrong day.
    private func appendDiaryOpEcho(_ echo: String) {
        let trimmed = echo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let text = "Diary update: \(trimmed)."
        do {
            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: text,
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                )
            )
            messages.append(assistantMessage)
            trimVisibleChatHistory()
        } catch {
            // Non-fatal: mutation already applied.
        }
    }

    private func snapshotMeals(for payload: FoodLogPayload) throws -> MealDeleteSnapshot? {
        var meals: [MealRecord] = []
        if let idString = payload.mealID, let id = UUID(uuidString: idString),
           let meal = try persistence.nutrition.fetchMeal(id: id) {
            meals = [meal]
        } else if let dayRaw = payload.helmDay,
                  let helmDay = CalendarQueryPlanner.parseHelmDay(dayRaw) {
            meals = try persistence.nutrition.fetchMeals(for: helmDay)
            if let bucketRaw = payload.bucket,
               let bucket = MealBucket(rawValue: bucketRaw.lowercased()) {
                meals = meals.filter { $0.bucket == bucket }
            }
        }
        guard !meals.isEmpty else { return nil }
        let items = try meals.map { meal in
            MealDeleteSnapshot.Item(
                meal: meal,
                lineItems: try persistence.foodLog.fetchLineItems(for: meal.id)
            )
        }
        return MealDeleteSnapshot(items: items)
    }

    private func persistMealDeleteUndo(snapshot: MealDeleteSnapshot) {
        let messageID = messages.last(where: { $0.role == .assistant })?.id ?? UUID().uuidString
        let json = (try? JSONEncoder().encode(snapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let action = CoachAppliedAction(
            messageID: messageID,
            kind: .mealDelete,
            snapshotJSON: json
        )
        do {
            try persistence.coachAppliedActions.insert(action)
            undoableActionsByMessageID[messageID] = action
        } catch {
            CoachDiagnosticsStore.shared.recordFailure(surface: "coachAppliedAction", error: error)
        }
    }

    private func persistScheduleUndo(prior: StoredScheduleOverrides, caption: String) {
        let messageID = messages.last(where: { $0.role == .assistant })?.id ?? UUID().uuidString
        let snapshot = ScheduleOverrideSnapshot(overrides: prior, caption: caption)
        let json = (try? JSONEncoder().encode(snapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let action = CoachAppliedAction(
            messageID: messageID,
            kind: .scheduleAdjustment,
            snapshotJSON: json
        )
        do {
            try persistence.coachAppliedActions.insert(action)
            undoableActionsByMessageID[messageID] = action
        } catch {
            CoachDiagnosticsStore.shared.recordFailure(surface: "coachAppliedAction", error: error)
        }
    }

    private func restoreScheduleOverrides(_ snapshot: ScheduleOverrideSnapshot) async throws {
        if snapshot.overrides.isEmpty {
            try persistence.scheduleOverrides.clear()
        } else {
            try persistence.scheduleOverrides.save(snapshot.overrides)
        }
        let today = HelmDay.day(for: Date(), calendar: .current)
        PrescriptionDayStore.clear(for: today)
        await HelmActionRuntime.apply(
            HelmActionResult(sideEffects: [.refreshPrescription]),
            after: .coach
        )
    }

    private func restoreDeletedMeals(_ snapshot: MealDeleteSnapshot) async throws {
        for item in snapshot.items {
            let meal = item.meal
            if item.lineItems.isEmpty {
                _ = try await HelmActionRuntime.perform(
                    .meal(.logQuickAdd(
                        kilocalories: meal.energy?.kilocalories ?? 0,
                        proteinG: meal.proteinGrams ?? 0,
                        carbsG: meal.carbohydrateGrams ?? 0,
                        fatG: meal.fatGrams ?? 0,
                        label: meal.name,
                        bucket: meal.bucket,
                        loggedAt: meal.loggedAt,
                        helmDay: meal.helmDay,
                        mealID: meal.id.uuidString
                    )),
                    after: .coach
                )
            } else {
                _ = try await HelmActionRuntime.perform(
                    .meal(.logComposite(
                        name: meal.name,
                        bucket: meal.bucket,
                        lineItems: item.lineItems,
                        loggedAt: meal.loggedAt,
                        helmDay: meal.helmDay,
                        mealID: meal.id.uuidString,
                        source: meal.source
                    )),
                    after: .coach
                )
            }
        }
    }
}
