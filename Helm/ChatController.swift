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
            messages = try persistence.chat.fetchAll()
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
            clearChatProgress()
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
        guard !trimmed.isEmpty, !isStreaming else { return }
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
                _ = try await NutritionBootstrap.manualMealService.logQuickAdd(
                    kilocalories: estimate.caloriesKcal,
                    proteinG: estimate.proteinG,
                    carbsG: estimate.carbsG,
                    fatG: estimate.fatG,
                    label: resolvedName,
                    bucket: bucket,
                    loggedAt: loggedAt,
                    helmDay: pending.helmDay,
                    mealID: mealID.uuidString
                )
            } else {
                _ = try await NutritionBootstrap.manualMealService.logCompositeMeal(
                    name: resolvedName,
                    bucket: bucket,
                    lineItems: records,
                    loggedAt: loggedAt,
                    mealID: mealID.uuidString,
                    source: .manual
                )
            }

            NutritionBootstrap.lastViewedHelmDay = pending.helmDay
            NutritionBootstrap.refreshNutrition(for: pending.helmDay)
            pendingFoodMealConfirm = nil
            lastTurnError = nil
            CoachApplyMomentStore.shared.play()
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
                let applier = FoodLogCommandApplier(
                    manualMealService: NutritionBootstrap.manualMealService,
                    persistence: persistence
                )
                try await applier.apply(payload)
                let loggedHelmDay = FoodLogCommandApplier.resolvedHelmDay(
                    from: payload,
                    now: Date(),
                    calendar: .current
                )
                NutritionBootstrap.lastViewedHelmDay = loggedHelmDay
                NutritionBootstrap.refreshNutrition(for: loggedHelmDay)
                CoachApplyMomentStore.shared.play()
            case let .mealCopy(payload):
                applyProgressStep = "Copying meal…"
                guard let resolved = MealCopyCommandApplier.resolvedDays(payload) else {
                    throw ManualMealError.invalidQuickAdd
                }
                _ = try await NutritionBootstrap.mealRepeatService.copyBucket(
                    from: resolved.source,
                    bucket: resolved.sourceBucket,
                    to: resolved.target,
                    targetBucket: resolved.targetBucket
                )
                NutritionBootstrap.lastViewedHelmDay = resolved.target
                NutritionBootstrap.refreshNutrition(for: resolved.target)
                CoachApplyMomentStore.shared.play()
            case let .memoryAdjustment(payload):
                applyProgressStep = "Updating Memory…"
                try CoachMemoryAdjuster.apply(payload, persistence: persistence)
                CoachApplyMomentStore.shared.play()
            case let .workoutStart(payload):
                applyProgressStep = "Preparing session…"
                let today = HelmDay.day(for: .now, calendar: .current)
                try await applyWorkoutStart(payload, helmDay: today)
                CoachApplyMomentStore.shared.play()
            case let .settingsAdjustment(payload):
                applyProgressStep = "Updating plan…"
                try CoachPlanSettingsAdjuster.apply(payload, persistence: persistence)
                await PlanBootstrap.prescriptionService.refresh(
                    readiness: ReadinessBootstrap.readinessService.state.score
                )
                CoachApplyMomentStore.shared.play()
            case let .reactiveDeload(payload):
                applyProgressStep = "Updating plan…"
                if payload.action == .confirm {
                    try await PlanBootstrap.prescriptionService.confirmReactiveDeload()
                } else {
                    try await PlanBootstrap.prescriptionService.dismissReactiveDeload()
                }
                await PlanBootstrap.prescriptionService.refresh(
                    readiness: ReadinessBootstrap.readinessService.state.score
                )
                CoachApplyMomentStore.shared.play()
            case let .planRegenerate:
                applyProgressStep = "Regenerating…"
                let today = HelmDay.day(for: .now, calendar: .current)
                PrescriptionDayStore.clear(for: today)
                await PlanBootstrap.prescriptionService.refresh(
                    readiness: ReadinessBootstrap.readinessService.state.score
                )
                CoachApplyMomentStore.shared.play()
            }
            pendingChatAction = nil
            lastTurnError = nil
        } catch {
            lastTurnError = error.localizedDescription
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatAction", error: error)
        }
    }

    private func applyWorkoutStart(_ payload: WorkoutStartPayload, helmDay: HelmDay) async throws {
        try await CoachWorkoutStartAdjuster.start(
            payload: payload,
            helmDay: helmDay,
            persistence: persistence,
            prescriptionService: PlanBootstrap.prescriptionService
        ) { action in
            switch action {
            case let .prescription(useAdjusted):
                try await WorkoutStartCoordinator.startTodaysSession(
                    controller: TrainBootstrap.sessionController,
                    prescriptionService: PlanBootstrap.prescriptionService,
                    openTrainTab: true,
                    useAdjustedPrescription: useAdjusted
                )
            case let .importedPlan(plan):
                try await WorkoutStartCoordinator.startImportedPlan(
                    controller: TrainBootstrap.sessionController,
                    plan: plan,
                    openTrainTab: true
                )
            }
        }
    }

    private func sendMessage(_ text: String, coachUserMessage: String? = nil) async {
        let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)
        let availability = await provider.availability()
        guard availability.isAvailable else {
            isFoodDictationTurn = false
            isCoachAvailable = false
            if case .unavailable(let label, let helpText) = availability {
                degradedState = CoachDegradedState(
                    mode: .engineOnly,
                    reason: .providerUnavailable,
                    userMessage: helpText ?? label
                )
            } else {
                degradedState = CoachDegradedState.offline
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

            let profile = try persistence.memoryProfile.load()
            let endDay = HelmDay.day(for: .now, calendar: .current)
            let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
            let thread = CoachThreadState(
                messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
            ).windowed()
            let turn: ContextTurn = thread.isFollowUp ? .followUp : .initial
            let reserved = TokenBudget.estimateTokens(
                characterCount: thread.messages.reduce(0) { $0 + $1.text.count }
            ) + 2_048
            let budget = max(
                4_096,
                TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider) - reserved
            )
            let prompt = ContextBuilder.build(
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
            var assembled = try await streamAssistantText(
                provider: provider,
                systemInstructions: prompt.systemInstructions,
                contextBlock: prompt.contextBlock,
                userMessage: providerUserMessage,
                thread: thread,
                allowEmptyRetry: true
            )

            if let mealQuery = MealQueryPayloadParser.parse(from: assembled) {
                assembled = try await runMealQueryFollowUp(
                    query: mealQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            } else if let inferred = CoachChatIntent.inferredMealQuery(from: text) {
                assembled = try await runMealQueryFollowUp(
                    query: inferred,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            }

            if let recoveryQuery = RecoveryQueryPayloadParser.parse(from: assembled) {
                assembled = try await runRecoveryQueryFollowUp(
                    query: recoveryQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            } else if let inferred = CoachChatIntent.inferredRecoveryQuery(from: text) {
                assembled = try await runRecoveryQueryFollowUp(
                    query: inferred,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            }

            if let calendarQuery = CalendarQueryPayloadParser.parse(from: assembled) {
                assembled = try await runCalendarQueryFollowUp(
                    query: calendarQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            } else if let inferred = CoachChatIntent.inferredCalendarQuery(from: text) {
                assembled = try await runCalendarQueryFollowUp(
                    query: inferred,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            }

            if let trendsQuery = TrendsQueryPayloadParser.parse(from: assembled) {
                assembled = try await runTrendsQueryFollowUp(
                    query: trendsQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            } else if let inferred = CoachChatIntent.inferredTrendsQuery(from: text) {
                assembled = try await runTrendsQueryFollowUp(
                    query: inferred,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            }

            if let workoutQuery = WorkoutQueryPayloadParser.parse(from: assembled) {
                assembled = try await runWorkoutQueryFollowUp(
                    query: workoutQuery,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            } else if let inferred = CoachChatIntent.inferredWorkoutQuery(from: text) {
                assembled = try await runWorkoutQueryFollowUp(
                    query: inferred,
                    provider: provider,
                    profile: profile,
                    endDay: endDay,
                    priorAssembled: assembled
                )
            }

            if CoachChatIntent.looksLikeWorkoutStart(text),
               !CoachChatIntent.looksLikeWorkoutReview(text),
               needsStructuredWorkoutStart(assembled: assembled, userText: text),
               let gemini = provider as? GeminiProvider
            {
                assembled = try await runStructuredWorkoutStart(
                    gemini: gemini,
                    profile: profile,
                    contextDays: contextDays,
                    thread: thread,
                    userText: text,
                    priorAssembled: assembled
                )
            }

            let pendingAction: CoachChatActionProposal?
            if isFoodDictationTurn,
               let foodPayload = FoodLogPayloadParser.parse(from: assembled),
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
                pendingAction = CoachChatActionParser.proposal(from: assembled)
                pendingChatAction = pendingAction
            }
            let userFacingText = CoachChatDisplayText.assistantText(
                from: assembled,
                pendingAction: pendingAction
            )

            guard !userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || pendingAction != nil
                || pendingFoodMealConfirm != nil
            else {
                throw CoachStructuredOutputError.emptyResponse
            }

            // Never persist a blank assistant row; confirmation card can stand alone when reply is empty.
            if !userFacingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let assistantMessage = try persistence.chat.append(
                    ChatMessageInsert(
                        role: .assistant,
                        text: userFacingText,
                        promptVersion: CoachPromptVersion.chatV1.rawValue,
                        schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                    )
                )
                messages.append(assistantMessage)
            }
            lastFailedUserMessage = nil
            CoachDiagnosticsStore.shared.clear()

            if pendingAction == nil, FoodLogPayloadParser.hasMalformedBlock(in: assembled) {
                lastTurnError = "Couldn't read that meal log. Ask again with calories."
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
            degradedState = CoachFailurePolicy.degradedState(for: error)
            lastTurnError = degradedState?.userMessage
            CoachDiagnosticsStore.shared.recordFailure(surface: "chat", error: error)
            await logTurn(
                status: "failed",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                messageCount: messages.count,
                error: error
            )
        }
    }

    private func streamAssistantText(
        provider: any CoachLLMProvider,
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        allowEmptyRetry: Bool
    ) async throws -> String {
        for attempt in 0 ... (allowEmptyRetry ? 1 : 0) {
            isStreaming = true
            streamingText = attempt == 0 ? "" : "Retrying…"
            let stream = try await provider.respond(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            )
            var assembled = ""
            do {
                for try await chunk in stream {
                    try Task.checkCancellation()
                    assembled += chunk
                    streamingText = assembled
                }
            } catch is CancellationError {
                isStreaming = false
                streamingText = nil
                throw CancellationError()
            }
            isStreaming = false
            streamingText = nil
            if !assembled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return assembled
            }
            if attempt == 0, allowEmptyRetry {
                continue
            }
            throw CoachStructuredOutputError.emptyResponse
        }
        throw CoachStructuredOutputError.emptyResponse
    }

    private func needsStructuredWorkoutStart(assembled: String, userText: String) -> Bool {
        guard let payload = WorkoutStartPayloadParser.parse(from: assembled) else {
            return true
        }
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
        gemini: GeminiProvider,
        profile: MemoryProfile,
        contextDays: CoachContextDays,
        thread: CoachThreadState,
        userText: String,
        priorAssembled: String
    ) async throws -> String {
        let budget = TokenBudget.maxInputTokens(for: .gemini)
        let prompt = ContextBuilder.build(
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
        let artefact = try await gemini.generateWorkoutStart(
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
        return try artefact.payload.chatAssemblyText()
    }

    private func runWorkoutQueryFollowUp(
        query: WorkoutQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> String {
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
        let prompt = ContextBuilder.build(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantText(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true
        )
    }

    private func runRecoveryQueryFollowUp(
        query: RecoveryQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> String {
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
        let prompt = ContextBuilder.build(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantText(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true
        )
    }

    private func runCalendarQueryFollowUp(
        query: CalendarQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> String {
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
        let prompt = ContextBuilder.build(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantText(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true
        )
    }

    private func runTrendsQueryFollowUp(
        query: TrendsQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> String {
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
        let prompt = ContextBuilder.build(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantText(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true
        )
    }

    private func runMealQueryFollowUp(
        query: MealQueryPayload,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        endDay: HelmDay,
        priorAssembled: String
    ) async throws -> String {
        let service = MealHistoryQueryService(store: persistence)
        let results = try service.run(query)
        let toolMessage = """
        # Meal query results
        \(results)

        Answer the athlete using these results. If they asked to copy a meal, emit meal_copy.v1. Do not invent foods not listed.
        """

        isStreaming = true
        streamingText = "Looking up meals…"

        let contextDays = try await CoachContextBootstrap.assemble(from: persistence, endingAt: endDay)
        let thread = CoachThreadState(
            messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
                + [CoachMessage(role: .assistant, text: CoachChatTextFormatter.userFacingText(from: priorAssembled))]
        ).windowed()
        let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
        let prompt = ContextBuilder.build(
            profile: profile,
            days: contextDays,
            budget: budget,
            turn: .followUp
        )

        return try await streamAssistantText(
            provider: provider,
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: toolMessage,
            thread: thread,
            allowEmptyRetry: true
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
            context["error"] = String(describing: type(of: error))
        }
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: error == nil ? .info : .error,
            message: "Chat turn \(status)",
            context: context
        )
    }
}
