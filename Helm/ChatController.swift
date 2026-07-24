import CoachLLM
import Core
import Diagnostics
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
        cancelStreaming()
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

            let assistantMessage = try persistence.chat.append(
                ChatMessageInsert(
                    role: .assistant,
                    text: assembled,
                    promptVersion: CoachPromptVersion.chatV1.rawValue,
                    schemaVersion: CoachOutputSchemaVersion.chatV1.rawValue
                )
            )
            messages.append(assistantMessage)

            if (try? CoachPlanSettingsAdjuster.tryApplyEmbeddedJSON(in: assembled, persistence: persistence)) == true {
                await PlanBootstrap.prescriptionService.refresh(
                    readiness: ReadinessBootstrap.readinessService.state.score
                )
            }

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
