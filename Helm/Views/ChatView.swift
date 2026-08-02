import DesignSystem
import CoachLLM
import Persistence
import SwiftUI

struct ChatView: View {
    @Bindable private var controller = ChatBootstrap.controller
    @Bindable private var activityGate = CoachActivityGate.shared
    @FocusState private var isInputFocused: Bool

    private var coachName: String { CoachDisplayNameStore.name }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let degradedState = controller.degradedState {
                    offlineBanner(degradedState)
                }

                if let message = activityGate.blockingMessage(for: .chat) {
                    blockingBanner(message)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: HelmSpacing.md) {
                            if controller.messages.isEmpty,
                               !controller.isStreaming,
                               controller.lastTurnError == nil,
                               controller.pendingChatAction == nil {
                                emptyState
                            }

                            ForEach(controller.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if let lastTurnError = controller.lastTurnError, controller.pendingChatAction == nil {
                                errorBubble(lastTurnError)
                                    .id("last-turn-error")
                            }

                            if let proposal = controller.pendingChatAction {
                                CoachActionConfirmationCard(
                                    title: proposal.title,
                                    detail: proposal.detail,
                                    reason: proposal.reason,
                                    errorMessage: controller.lastTurnError.map { chatActionErrorCopy($0) },
                                    confirmLabel: proposal.confirmLabel,
                                    cancelLabel: proposal.cancelLabel,
                                    isRetryDisabled: controller.isApplyingChatAction,
                                    onConfirm: { controller.confirmChatAction() },
                                    onCancel: { controller.dismissChatAction() },
                                    onRetry: { controller.confirmChatAction() }
                                )
                                .id("chat-confirmation")
                            }

                            if controller.isStreaming, let streamingText = controller.streamingText {
                                if shouldShowStreamingBubble(streamingText) {
                                    assistantBubble(streamingText, isStreaming: true)
                                        .id("streaming")
                                }
                            }
                        }
                        .padding(HelmSpacing.md)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: controller.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.streamingText) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.pendingChatAction?.id) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                if controller.isApplyingChatAction {
                    CoachAIProgressCard(
                        eyebrow: "COACH",
                        title: "Applying change",
                        completedSteps: ["Confirmed"],
                        currentStep: controller.applyProgressStep ?? "Working…",
                        isImpactful: true
                    )
                    .helmScreenPadding()
                    .padding(.vertical, HelmSpacing.sm)
                    .helmPanelChrome(.surface)
                    .transition(.opacity)
                }

                composer
            }
            .helmScreenBackground()
            .navigationTitle("Chat")
            .onAppear {
                Task { await controller.onAppear() }
                controller.consumeHandoffPromptIfNeeded()
            }
            .onChange(of: controller.handoffGeneration) { _, _ in
                controller.consumeHandoffPromptIfNeeded()
            }
            .onDisappear {
                controller.onDisappear()
            }
        }
    }

    private func blockingBanner(_ message: String) -> some View {
        Text(message)
            .helmType(.body, color: HelmColor.depleted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surface)
    }

    private var emptyState: some View {
        HelmEmptyState(
            title: "Ask why",
            message: "Coach answers from your readiness, training, and nutrition data. Offline keeps numbers and logging working.",
            icon: .chat
        )
        .padding(.top, HelmSpacing.xl)
    }

    private func offlineBanner(_ state: CoachDegradedState) -> some View {
        HStack(spacing: HelmSpacing.sm) {
            HelmIconView(.offline, context: .inline)
                .foregroundStyle(HelmColor.fgSecondary)
            Text(state.userMessage)
                .helmType(.body, color: HelmColor.fgSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface)
    }

    private func messageBubble(_ message: StoredChatMessage) -> some View {
        Group {
            switch message.role {
            case .user:
                CoachMessageBubble(role: .user, text: message.text, coachName: coachName)
            case .assistant:
                let display = CoachChatTextFormatter.userFacingText(from: message.text)
                let chart = ChartPayloadParser.parse(from: message.text)
                if display.isEmpty, chart == nil {
                    EmptyView()
                } else {
                    assistantBubble(message.text, isStreaming: false)
                }
            case .system:
                EmptyView()
            }
        }
    }

    private func assistantBubble(_ text: String, isStreaming: Bool) -> some View {
        let display = CoachChatTextFormatter.userFacingText(from: text)
        let chart = isStreaming ? nil : ChartPayloadParser.parse(from: text)
        return HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                if !display.isEmpty || isStreaming {
                    CoachMessageBubble(
                        role: .assistant,
                        text: display,
                        isStreaming: isStreaming,
                        coachName: coachName
                    )
                }

                if let chart {
                    CoachChatChartBubble(payload: chart)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(coachName.uppercased())
                        .helmType(.monoTag, color: HelmColor.depleted)
                    Text(chatActionErrorCopy(message))
                        .helmType(.body, color: HelmColor.depleted)
                }
                if controller.lastFailedUserMessage != nil {
                    Button("Try again") {
                        controller.retryLastTurn()
                    }
                    .buttonStyle(.helmSecondary)
                }
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .helmPanelChrome(.surface)
            Spacer(minLength: HelmSpacing.xl)
        }
    }

    private func chatActionErrorCopy(_ message: String) -> String {
        guard let pending = controller.pendingChatAction else {
            return "Could not respond. \(message)"
        }
        switch pending.kind {
        case .workoutStart:
            return "Could not start. \(message)"
        case .foodLog, .mealCopy:
            return "Could not apply. \(message)"
        }
    }

    /// Hide the "..." flash while a structured-only payload streams in.
    private func shouldShowStreamingBubble(_ text: String) -> Bool {
        let display = CoachChatTextFormatter.userFacingText(from: text)
        if !display.isEmpty { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return !(trimmed.hasPrefix("{") || trimmed.hasPrefix("```"))
    }

    private var composer: some View {
        HStack(spacing: HelmSpacing.sm) {
            TextField("Ask the coach", text: $controller.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .helmPanelChrome(.elevated)
                .focused($isInputFocused)
                .disabled(!controller.isCoachAvailable || controller.isStreaming || activityGate.isBlocked(for: .chat))

            Button {
                HapticEngine.shared.play(.selection)
                controller.send()
                isInputFocused = false
            } label: {
                HelmIconView(.send, context: .action)
                    .foregroundStyle(
                        canSend ? HelmColor.accent : HelmColor.fgMuted
                    )
            }
            .buttonStyle(.helmPressable)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(HelmSpacing.md)
        .helmPanelChrome(.surface)
    }

    private var canSend: Bool {
        controller.isCoachAvailable
            && !controller.isStreaming
            && !activityGate.isBlocked(for: .chat)
            && !controller.draftText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            if controller.isStreaming,
               let streamingText = controller.streamingText,
               shouldShowStreamingBubble(streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if controller.pendingChatAction != nil {
                proxy.scrollTo("chat-confirmation", anchor: .bottom)
            } else if controller.lastTurnError != nil {
                proxy.scrollTo("last-turn-error", anchor: .bottom)
            } else if let lastID = controller.messages.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        if animated {
            withAnimation { scroll() }
        } else {
            scroll()
        }
    }
}

#Preview("Chat instrument") {
    ChatView()
        .helmTheme()
        .environment(\.helmSkin, .instrument)
}

#Preview("Chat signal") {
    ChatView()
        .helmTheme()
        .environment(\.helmSkin, .signal)
}

#Preview("Chat empty") {
    ScrollView {
        HelmEmptyState(
            title: "Ask why",
            message: "Coach answers from your readiness, training, and nutrition data.",
            icon: .chat
        )
        .padding()
    }
    .helmTheme()
}

#Preview("Chat error") {
    ScrollView {
        HelmErrorState(
            title: "Coach unavailable",
            message: "Could not reach the coach provider.",
            onRetry: {}
        )
        .padding()
    }
    .helmTheme()
}

#Preview("Chat loading") {
    ScrollView {
        HelmLoadingState(rowCount: 2)
            .padding()
    }
    .helmTheme()
}
