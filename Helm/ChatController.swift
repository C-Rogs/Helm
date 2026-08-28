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
    private(set) var pendingChatAction: CoachChatActionProposal?
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
    /// Date of the last refinement extraction for debouncing.
    private var lastRefinementExtractionDate: Date?

    private let persistence: PersistenceStore
    private let providerPreferences: ProviderPreferencesStore
    private var streamTask: Task<Void, Never>?
    private var isFoodDictationTurn = false

    init(
        persistence: PersistenceStore,
        providerPreferences: ProviderPreferencesStore = ProviderPreferencesStore()
    ) {
        self.persistence = persistence
        self.providerPreferences = providerPreferences
    }

    func onAppear() async {
        loadHistory()
        await refreshAvailability()
    }

    func onDisappear() {
        // Keep streaming when switching tabs so Chat and in-session coach can run in parallel.
    }

    func retryLastTurn() {
        guard let lastFailedUserMessage, !isStreaming else { return }
        draftText = lastFailedUserMessage
        send()
    }

    func loadHistory() {
        do {
            messages = try persistence.chat.fetchRecent(limit: 100)
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
            messages = []
            pendingChatAction = nil
            pendingFoodMealConfirm = nil
            lastTurnError = nil
            lastFailedUserMessage = nil
            streamingText = nil
            citationValidation = nil
            pendingMemoryRefinements = []
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

    func send() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
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

        draftText = ""
        streamTask?.cancel()
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
        pendingChatAction = nil
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
            } catch {
                lastTurnError = error.localizedDescription
            }
        }
    }

    func dismissMemoryRefinements() {
        pendingMemoryRefinements = []
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
        } catch {
            lastTurnError = error.localizedDescription
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
            switch proposal.kind {
            case let .foodLog(payload):
                applyProgressStep = "Writing to diary…"
                _ = try await HelmActionRuntime.perform(
                    .meal(.fromCoachPayload(payload, now: Date())),
                    after: .coach
                )
            case let .mealCopy(payload):
                applyProgressStep = "Copying meal…"
                guard let resolved = MealCopyCommandApplier.resolvedDays(payload) else {
                    throw ManualMealError.invalidQuickAdd
                }
                _ = try await HelmActionRuntime.perform(
                    .copyMeal(HelmCopyMealCommand(
                        sourceDay: resolved.source,
                        sourceBucket: resolved.sourceBucket,
                        targetDay: resolved.target,
                        targetBucket: resolved.targetBucket
                    )),
                    after: .coach
                )
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
                try persistence.coachAdviceRecords.insert(record)
                try persistence.coachAdviceRecords.supersedePending(
                    type: .workoutStart,
                    excluding: messageID
                )
            case let .settingsAdjustment(payload):
                applyProgressStep = "Updating plan…"
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.fromCoachPayload(payload)),
                    after: .coach
                )
            case let .reactiveDeload(payload):
                applyProgressStep = "Updating plan…"
                let action: HelmReactiveDeloadAction = payload.action == .confirm ? .confirm : .dismiss
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.reactiveDeload(action)),
                    after: .coach
                )
            case let .planRegenerate:
                applyProgressStep = "Regenerating…"
                let today = HelmDay.day(for: .now, calendar: .current)
                _ = try await HelmActionRuntime.perform(
                    .trainingPlan(.regenerateToday(today)),
                    after: .coach
                )
            }
            pendingChatAction = nil
            lastTurnError = nil
        } catch {
            lastTurnError = error.localizedDescription
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatAction", error: error)
        }
    }

    private func sendMessage(_ text: String, coachUserMessage: String? = nil) async {
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
                    ?? "Coach is unavailable. Try Search or add your Gemini API key in Settings."
            }
            return
        }

        isCoachAvailable = true
        degradedState = nil
        lastTurnError = nil
        lastFailedUserMessage = text
        if CoachChatIntent.clearsPendingWorkoutStart(text) {
            pendingChatAction = nil
        }
        if coachUserMessage != nil {
            beginFoodDictationProgress(step: "Sending to coach…")
        } else {
            clearChatProgress()
        }
        CoachActivityGate.shared.begin(.chat)
        defer { CoachActivityGate.shared.end(.chat) }

        do {
            let userMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .user,
                    text: text,
                    promptVersion: CoachPromptVersion.chatV1.rawValue
                )
            )
            messages.append(userMessage)

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
                messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
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

            let providerUserMessage = coachUserMessage ?? text
            var assembledTurn = try await streamAssistantTurn(
                provider: provider,
                systemInstructions: prompt.systemInstructions,
                contextBlock: prompt.contextBlock,
                userMessage: providerUserMessage,
                thread: thread,
                allowEmptyRetry: true,
                freshnessSuffix: prompt.freshnessSuffix
            )

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

            if let mealQuery {
                assembledTurn = try await runMealQueryFollowUp(
                    query: mealQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let recoveryQuery {
                assembledTurn = try await runRecoveryQueryFollowUp(
                    query: recoveryQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let calendarQuery {
                assembledTurn = try await runCalendarQueryFollowUp(
                    query: calendarQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let trendsQuery {
                assembledTurn = try await runTrendsQueryFollowUp(
                    query: trendsQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let workoutQuery {
                assembledTurn = try await runWorkoutQueryFollowUp(
                    query: workoutQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let nutritionQuery {
                assembledTurn = try await runNutritionQueryFollowUp(
                    query: nutritionQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }
            if let contextRefresh {
                assembledTurn = try await runContextRefreshFollowUp(
                    payload: contextRefresh,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembledTurn.text
                )
            }

            if CoachChatIntent.looksLikeWorkoutStart(text),
               !CoachChatIntent.looksLikeWorkoutReview(text),
               needsStructuredWorkoutStart(
                assembled: assembledTurn.text,
                functionCalls: assembledTurn.functionCalls,
                userText: text
               )
            {
                do {
                    assembledTurn = try await runStructuredWorkoutStart(
                        provider: provider,
                        profile: profile,
                        contextDays: contextDays,
                        thread: thread,
                        userText: text,
                        priorAssembled: assembledTurn.text
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
            let pendingAction: CoachChatActionProposal?
            let foodPayload = CoachChatActionParser.foodLogPayload(from: assembledTurn.functionCalls)
                ?? FoodLogPayloadParser.parse(from: assembledTurn.text)
            if wasFoodDictation,
               let foodPayload,
               foodPayload.action == .log {
                isFoodDictationTurn = false
                let bucket = resolvedFoodLogBucket(foodPayload.bucket)
                let helmDay = FoodLogCommandApplier.resolvedHelmDay(
                    from: foodPayload,
                    now: Date(),
                    calendar: .current
                )
                isPreparingFoodMealConfirm = true
                chatProgressCompletedSteps = ["Coach estimated your meal"]
                chatProgressStep = "Matching ingredients to CoFID…"
                await Task.yield()
                let estimate = FoodLogMealGrounding.groundedEstimate(from: foodPayload)
                isPreparingFoodMealConfirm = false
                clearChatProgress()
                pendingFoodMealConfirm = CoachFoodMealConfirmState(
                    estimate: estimate,
                    bucket: bucket,
                    helmDay: helmDay,
                    coachReply: foodPayload.reply
                )
                pendingChatAction = nil
                pendingAction = nil
            } else {
                isFoodDictationTurn = false
                clearChatProgress()
                pendingAction = CoachChatActionParser.proposal(
                    from: assembledTurn.text,
                    functionCalls: assembledTurn.functionCalls
                )
                pendingChatAction = pendingAction
            }

            var storedText = CoachChatTextFormatter.userFacingText(from: assembledTurn.text)
            if let chart = CoachCatalogQueryDecoder.chart(from: querySource.functionCalls)
                ?? ChartPayloadParser.parse(from: assembledTurn.text) {
                storedText = CoachChatChartStitcher.appending(chart, to: storedText)
            }
            let userFacingText = CoachChatDisplayText.assistantText(
                from: storedText,
                pendingAction: pendingAction
            )
            let hasChart = ChartPayloadParser.parse(from: storedText) != nil

            guard !userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || pendingAction != nil
                || pendingFoodMealConfirm != nil
                || hasChart
            else {
                throw CoachStructuredOutputError.emptyResponse
            }

            // Never persist a blank assistant row; confirmation card can stand alone when reply is empty.
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
            }

            if pendingAction == nil,
               pendingFoodMealConfirm == nil,
               let navigate = CoachCatalogQueryDecoder.navigate(from: querySource.functionCalls),
               let tab = AppTab(coachSurfaceLabel: navigate.tab) {
                AppTabRouter.shared.open(tab)
            }
            lastFailedUserMessage = nil
            CoachDiagnosticsStore.shared.clearTurnState()

            maybeTriggerMemoryRefinementExtraction(profile: profile)

            if pendingAction == nil,
               CoachChatActionParser.hasMalformedFoodLogCall(assembledTurn.functionCalls)
                || FoodLogPayloadParser.hasMalformedBlock(in: assembledTurn.text) {
                lastTurnError = "Couldn't read that meal log. Ask again with calories."
            } else if wasFoodDictation, pendingFoodMealConfirm == nil, lastTurnError == nil {
                // Nutrition describe has no chat transcript UI - prose-only replies looked like a hang.
                lastTurnError = "Couldn't estimate that meal. Try again with clearer portions, or use Search."
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
            isFoodDictationTurn = false
            clearChatProgress()
            isPreparingFoodMealConfirm = false
            isStreaming = false
            streamingText = nil
            CoachDiagnosticsStore.shared.clearTurnState()
            degradedState = CoachFailurePolicy.degradedState(for: error)
            lastTurnError = degradedState?.userMessage
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
            appSurface: currentAppSurface()
        )
    }

    private func currentAppSurface() -> CoachAppSurfaceSnapshot {
        let session = try? persistence.activeSessions.fetchActiveSnapshot(at: .now)
        return CoachAppSurfaceSnapshot(
            selectedTab: AppTabRouter.shared.selectedTab.coachSurfaceLabel,
            sessionStatus: session?.session.status.rawValue ?? "none",
            sessionTitle: session?.session.title
        )
    }

    private struct AssembledCoachTurn {
        var text: String
        var functionCalls: [CoachLLMFunctionCall]

        var isEmpty: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && functionCalls.isEmpty
        }
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
            streamingText = attempt == 0 ? "" : "Retrying…"
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
                        streamingText = assembled
                    case .functionCall(let call):
                        functionCalls.append(call)
                    }
                }
            } catch is CancellationError {
                isStreaming = false
                streamingText = nil
                throw CancellationError()
            }
            isStreaming = false
            streamingText = nil
            let turn = AssembledCoachTurn(text: assembled, functionCalls: functionCalls)
            if !turn.isEmpty {
                return turn
            }
            if attempt == 0, allowEmptyRetry {
                continue
            }
            throw CoachStructuredOutputError.emptyResponse
        }
        throw CoachStructuredOutputError.emptyResponse
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
        isStreaming = false
        streamingText = nil
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
            allowEmptyRetry: true,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runRecoveryQueryFollowUp(
        query: RecoveryQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
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
            allowEmptyRetry: true,
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

        Answer from these EventKit results. List real event titles and times. If engine_busy=true, explain the reason line (all-day, scheduled-hours threshold, or event-count threshold). If engine_busy=false, say the day is below the busy thresholds even if some events exist. Never invent events. If calendar_status is not authorized, tell the athlete to enable calendar access in Settings.
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

        return try await streamAssistantTurn(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runTrendsQueryFollowUp(
        query: TrendsQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = TrendsHistoryQueryService(store: persistence)
        let results = try service.run(query)
        let toolMessage = """
        # Trends query results
        \(results)

        Answer in chat-length style grounded in the numbers. Explain what the trend shows (up, down, stable) and what might be driving it. Not a raw metric dump.
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
            allowEmptyRetry: true,
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
            allowEmptyRetry: true,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runContextRefreshFollowUp(
        payload: ContextRefreshPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let labels = payload.blocks.joined(separator: ", ")
        let toolMessage = """
        # Context refresh
        Rebuilt: \(labels). Use the context block. Do not invent data. Do not request another context_refresh unless still stale.
        """

        isStreaming = true
        streamingText = "Refreshing context…"

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
            allowEmptyRetry: true,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func runMealQueryFollowUp(
        query: MealQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> AssembledCoachTurn {
        let service = MealHistoryQueryService(store: persistence)
        let results = try service.run(query)
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
            allowEmptyRetry: true,
            freshnessSuffix: prompt.freshnessSuffix
        )
    }

    private func resolvedFoodLogBucket(_ raw: String?) -> MealBucket {
        guard let raw else { return .snacks }
        return MealBucket(rawValue: raw.lowercased()) ?? .snacks
    }

    private func beginFoodDictationProgress(step: String) {
        chatProgressTitle = "Voice meal log"
        chatProgressCompletedSteps = []
        chatProgressStep = step
        isPreparingFoodMealConfirm = false
    }

    private func clearChatProgress() {
        chatProgressTitle = nil
        chatProgressCompletedSteps = []
        chatProgressStep = nil
        isPreparingFoodMealConfirm = false
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
    private func maybeTriggerMemoryRefinementExtraction(profile: MemoryProfile) {
        let substantiveTurns = messages.filter {
            $0.role == .user && $0.text.count > 50
        }
        guard substantiveTurns.count >= 3 else { return }
        guard lastRefinementExtractionDate == nil
            || Date().timeIntervalSince(lastRefinementExtractionDate!) >= 30 * 60
        else { return }

        let recentMessages = messages.suffix(20)
        let conversationText = recentMessages.map { msg in
            "\(msg.role == .user ? "Athlete" : "Coach"): \(msg.text)"
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
                    self.pendingMemoryRefinements = payload.refinements
                    self.lastRefinementExtractionDate = .now
                }
            } catch {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .coachLLM,
                    message: "Memory refinement extraction failed",
                    context: ["detail": String(error.localizedDescription.prefix(240))]
                )
                await MainActor.run { [weak self] in
                    self?.lastRefinementExtractionDate = .now
                }
            }
        }
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
}
