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
    private(set) var isApplyingChatAction = false
    private(set) var applyProgressStep: String?
    private(set) var handoffGeneration = 0
    private(set) var pendingHandoffPrompt: String?

    private let persistence: PersistenceStore
    private let providerPreferences: ProviderPreferencesStore
    private var streamTask: Task<Void, Never>?

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
        if CoachActivityGate.shared.isBlocked(for: .chat) {
            lastTurnError = CoachActivityGate.shared.blockingMessage(for: .chat)
            return
        }

        draftText = ""
        streamTask?.cancel()
        streamTask = Task {
            await sendMessage(trimmed)
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
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
        Task {
            await applyChatAction(proposal)
        }
    }

    func dismissChatAction() {
        pendingChatAction = nil
    }

    private func applyChatAction(_ proposal: CoachChatActionProposal) async {
        isApplyingChatAction = true
        applyProgressStep = "Applying change…"
        defer {
            isApplyingChatAction = false
            applyProgressStep = nil
            pendingChatAction = nil
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
                NutritionBootstrap.refreshNutrition()
                HapticEngine.shared.play(.phaseChange)
                HapticEngine.shared.play(.mealConfirmed)
            case let .workoutStart(payload):
                applyProgressStep = "Preparing session…"
                let today = HelmDay.day(for: .now, calendar: .current)
                try await applyWorkoutStart(payload, helmDay: today)
                HapticEngine.shared.play(.phaseChange)
                HapticEngine.shared.play(.coachAdjust)
            }
        } catch {
            lastTurnError = error.localizedDescription
            CoachDiagnosticsStore.shared.recordFailure(surface: "chatAction", error: error)
        }
    }

    private func applyWorkoutStart(_ payload: WorkoutStartPayload, helmDay: HelmDay) async throws {
        _ = try await CoachWorkoutStartAdjuster.tryStartFromEmbeddedJSON(
            in: encodedWorkoutStartBlock(payload),
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

    private func encodedWorkoutStartBlock(_ payload: WorkoutStartPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return json
    }

    private func sendMessage(_ text: String) async {
        let provider = ProviderRegistry.shared.provider(for: providerPreferences.selectedProvider)
        let availability = await provider.availability()
        guard availability.isAvailable else {
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
            let contextDays = try CoachContextAssembler.assemble(from: persistence, endingAt: endDay)
            let thread = CoachThreadState(
                messages: messages.map { CoachMessage(role: $0.role, text: $0.text) }
            )
            let turn: ContextTurn = thread.isFollowUp ? .followUp : .initial
            let budget = TokenBudget.maxInputTokens(for: providerPreferences.selectedProvider)
            let prompt = ContextBuilder.build(
                profile: profile,
                days: contextDays,
                budget: budget,
                turn: turn
            )

            isStreaming = true
            streamingText = ""

            let stream = try await provider.respond(
                systemInstructions: prompt.systemInstructions,
                contextBlock: prompt.contextBlock,
                userMessage: text,
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
                degradedState = CoachFailurePolicy.degradedState(for: CancellationError())
                await logTurn(
                    status: "cancelled",
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    messageCount: messages.count
                )
                return
            }

            isStreaming = false
            streamingText = nil

            guard !assembled.isEmpty else {
                throw CoachStructuredOutputError.emptyResponse
            }

            let userFacingText = CoachChatTextFormatter.userFacingText(from: assembled)

            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: userFacingText,
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                )
            )
            messages.append(assistantMessage)
            lastFailedUserMessage = nil
            CoachDiagnosticsStore.shared.clear()

            if (try? CoachPlanSettingsAdjuster.tryApplyEmbeddedJSON(in: assembled, persistence: persistence)) == true {
                await PlanBootstrap.prescriptionService.refresh(
                    readiness: ReadinessBootstrap.readinessService.state.score
                )
            }

            pendingChatAction = CoachChatActionParser.proposal(from: assembled)

            await logTurn(
                status: "completed",
                promptVersion: CoachPromptVersion.chatV1.rawValue,
                schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue,
                messageCount: messages.count
            )
        } catch {
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
