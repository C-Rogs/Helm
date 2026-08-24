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
                if let degradedState = controller.degradedState,
                   controller.lastTurnError == nil {
                    degradedBanner(degradedState)
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

                            if let lastTurnError = controller.lastTurnError,
                               controller.pendingChatAction == nil,
                               controller.pendingFoodMealConfirm == nil {
                                errorBubble(lastTurnError)
                                    .id("last-turn-error")
                            }

                            if showsCoachProgress {
                                chatProgressCard
                                    .id("chat-progress")
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

                            if !controller.pendingMemoryRefinements.isEmpty {
                                MemoryRefinementConfirmationCard(
                                    refinements: controller.pendingMemoryRefinements,
                                    onAcceptAll: { controller.acceptMemoryRefinements() },
                                    onDismiss: { controller.dismissMemoryRefinements() }
                                )
                                .id("memory-refinements")
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
                    .onChange(of: controller.pendingMemoryRefinements.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.isPreparingFoodMealConfirm) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.chatProgressStep) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                if controller.isApplyingChatAction, controller.pendingFoodMealConfirm == nil {
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

                if controller.citationFailureCount > 0, !controller.messages.isEmpty {
                    citationWarningPill
                }
            }
            .helmScreenBackground()
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !controller.messages.isEmpty {
                        Button("Clear") {
                            controller.clearConversation()
                        }
                        .disabled(controller.isStreaming || controller.isApplyingChatAction)
                    }
                }
            }
            .onAppear {
                // Handoff prompt must apply immediately; hydration waits for tab chrome.
                controller.consumeHandoffPromptIfNeeded()
                Task {
                    await AppTabRouter.shared.preferChromeOverContentLoad()
                    guard !Task.isCancelled else { return }
                    await controller.onAppear()
                }
            }
            .onChange(of: controller.handoffGeneration) { _, _ in
                controller.consumeHandoffPromptIfNeeded()
            }
            .onDisappear {
                controller.onDisappear()
            }
            .sheet(isPresented: Binding(
                get: { controller.pendingFoodMealConfirm != nil },
                set: { if !$0 { controller.dismissFoodMealConfirm() } }
            )) {
                if let state = controller.pendingFoodMealConfirm {
                    CoachFoodMealConfirmSheet(
                        state: state,
                        isSaving: controller.isApplyingChatAction,
                        errorMessage: controller.lastTurnError,
                        onCancel: { controller.dismissFoodMealConfirm() },
                        onConfirm: { estimate, name, bucket in
                            controller.confirmFoodMeal(estimate: estimate, name: name, bucket: bucket)
                        }
                    )
                }
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

    private func degradedBanner(_ state: CoachDegradedState) -> some View {
        HStack(spacing: HelmSpacing.sm) {
            HelmIconView(bannerIcon(for: state.reason), context: .inline)
                .foregroundStyle(HelmColor.fgSecondary)
            Text(state.userMessage)
                .helmType(.body, color: HelmColor.fgSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.vertical, HelmSpacing.sm)
        .background(HelmColor.surface)
    }

    private func bannerIcon(for reason: CoachDegradedReason) -> HelmIcon {
        switch reason {
        case .offline:
            .offline
        case .timeout, .rateLimited:
            .refresh
        case .providerUnavailable:
            .settings
        case .cancelled, .contextTooLarge:
            .info
        case .other:
            .error
        }
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
                    if let caption = schemaActionCaption(for: message.text) {
                        actionCaption(caption)
                    } else {
                        EmptyView()
                    }
                } else {
                    assistantBubble(message.text, isStreaming: false)
                }
            case .system:
                EmptyView()
            }
        }
    }

    private func schemaActionCaption(for text: String) -> String? {
        guard let block = CoachEmbeddedJSONBlockFinder.blocks(in: text).first else { return nil }
        let sanitized = CoachJSONSanitizer.sanitize(block)
        guard let data = sanitized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = object["schemaVersion"] as? String
        else { return nil }

        switch schemaVersion {
        case CoachOutputSchemaVersion.settingsAdjustmentV1.rawValue:
            return "Coach updated training plan settings."
        case CoachOutputSchemaVersion.reactiveDeloadV1.rawValue:
            return "Coach proposed a deload week."
        case CoachOutputSchemaVersion.planRegenerateV1.rawValue:
            return "Coach regenerated today's plan."
        case CoachOutputSchemaVersion.foodLogV1.rawValue:
            return "Coach logged a meal."
        case CoachOutputSchemaVersion.mealCopyV1.rawValue:
            return "Coach copied a meal."
        case CoachOutputSchemaVersion.memoryAdjustmentV1.rawValue:
            return "Coach updated Memory."
        case CoachOutputSchemaVersion.workoutStartV1.rawValue,
             CoachOutputSchemaVersion.workoutStartV2.rawValue:
            return "Coach prepared a workout."
        case CoachOutputSchemaVersion.chartV1.rawValue:
            return "Coach created a chart."
        case CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue,
             CoachOutputSchemaVersion.sessionAdjustmentV2.rawValue:
            return "Coach adjusted this session."
        case CoachOutputSchemaVersion.mealEstimateV1.rawValue:
            return "Coach estimated a meal."
        case CoachOutputSchemaVersion.mealDecompositionV1.rawValue:
            return "Coach broke down a meal."
        case CoachOutputSchemaVersion.mealQueryV1.rawValue:
            return "Coach ran a meal query."
        case CoachOutputSchemaVersion.workoutQueryV1.rawValue:
            return "Coach ran a workout query."
        case CoachOutputSchemaVersion.recoveryQueryV1.rawValue:
            return "Coach ran a recovery query."
        case CoachOutputSchemaVersion.calendarQueryV1.rawValue:
            return "Coach ran a calendar query."
        case CoachOutputSchemaVersion.trendsQueryV1.rawValue:
            return "Coach ran a trends query."
        case CoachOutputSchemaVersion.calendarEventClassifyV1.rawValue:
            return "Coach classified calendar events."
        default:
            return nil
        }
    }

    private func actionCaption(_ text: String) -> some View {
        HStack {
            Text(text)
                .helmType(.label, color: HelmColor.fgMuted)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
            Spacer(minLength: 0)
        }
    }

    private func assistantBubble(_ text: String, isStreaming: Bool) -> some View {
        let display = CoachChatTextFormatter.userFacingText(from: text)
        let chart = isStreaming ? nil : ChartPayloadParser.parse(from: text)
        let sourceTags = isStreaming ? [] : CoachChatTextFormatter.sourceTags(from: text)
        return HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                if !display.isEmpty {
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

                if !sourceTags.isEmpty {
                    sourceTagChips(sourceTags)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func chipIcon(for kind: CoachChatSourceTag.Kind) -> HelmIcon {
        switch kind {
        case .evidence: return .brain
        case .topic: return .book
        case .engine: return .flame
        }
    }

    private func chipColor(for kind: CoachChatSourceTag.Kind) -> Color {
        switch kind {
        case .evidence: return HelmColor.surface
        case .topic: return HelmColor.surface
        case .engine: return HelmColor.surfaceEngineTag
        }
    }

    private func sourceTagChips(_ tags: [CoachChatSourceTag]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HelmSpacing.sm) {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        HelmIconView(chipIcon(for: tag.kind), context: .inline)
                            .imageScale(.small)
                        Text(tag.display)
                            .lineLimit(1)
                    }
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(chipColor(for: tag.kind), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, HelmSpacing.md)
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
                    #if DEBUG
                    if let detail = CoachDiagnosticsStore.shared.lastRejectReason,
                       !detail.isEmpty,
                       detail != message {
                        Text(detail)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                            .textSelection(.enabled)
                    }
                    if let code = CoachDiagnosticsStore.shared.lastErrorCode {
                        Text(code)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                            .textSelection(.enabled)
                    }
                    #endif
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
        case .foodLog, .mealCopy, .memoryAdjustment, .settingsAdjustment, .reactiveDeload, .planRegenerate:
            return "Could not apply. \(message)"
        }
    }

    /// Hide structured-only / JSON payloads while streaming so the athlete never sees raw schema.
    private func shouldShowStreamingBubble(_ text: String) -> Bool {
        let display = CoachChatTextFormatter.userFacingText(from: text)
        if !display.isEmpty { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") { return false }
        if trimmed.contains("\"schemaVersion\"") { return false }
        return true
    }

    private var composer: some View {
        HStack(spacing: HelmSpacing.sm) {
            Button {
                HapticEngine.shared.play(.selection)
                isInputFocused = true
            } label: {
                HelmIconView(.mic, context: .action)
                    .foregroundStyle(canUseMic ? HelmColor.fgSecondary : HelmColor.fgMuted)
            }
            .buttonStyle(.helmPressable)
            .disabled(!canUseMic)
            .accessibilityLabel("Show keyboard dictation")
            .accessibilityHint("Opens the keyboard. Use its Dictation button to speak.")

            TextField(
                "Ask the coach",
                text: $controller.draftText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .helmPanelChrome(.elevated)
                .focused($isInputFocused)
                .disabled(isComposerDisabled)

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

    private var showsCoachProgress: Bool {
        controller.isPreparingFoodMealConfirm
            || (controller.isStreaming
                && !shouldShowStreamingBubble(controller.streamingText ?? ""))
            || (controller.chatProgressStep != nil && controller.isStreaming)
    }

    private var chatProgressCard: some View {
        CoachAIProgressCard(
            eyebrow: "COACH",
            title: controller.chatProgressTitle ?? "Working on it",
            completedSteps: controller.chatProgressCompletedSteps,
            currentStep: controller.chatProgressStep ?? "Please wait…",
            footnote: controller.isPreparingFoodMealConfirm
                ? "Signal matches each ingredient to CoFID on your phone."
                : nil,
            isImpactful: true
        )
    }

    private var isComposerDisabled: Bool {
        !controller.isCoachAvailable
            || controller.isStreaming
            || controller.isPreparingFoodMealConfirm
            || controller.pendingFoodMealConfirm != nil
            || activityGate.isBlocked(for: .chat)
    }

    private var canUseMic: Bool {
        !isComposerDisabled && !controller.isApplyingChatAction
    }

    private var canSend: Bool {
        canUseMic
            && !controller.draftText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    private var citationWarningPill: some View {
        HStack(spacing: 6) {
            HelmIconView(.error, context: .inline)
                .imageScale(.small)
                .foregroundStyle(HelmColor.warning)
            Text("Coach cited \(controller.citationFailureCount) unverified source\(controller.citationFailureCount == 1 ? "" : "s") this session.")
                .helmType(.monoTag, color: HelmColor.warning)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.vertical, HelmSpacing.xs)
        .background(HelmColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, HelmSpacing.md)
        .padding(.bottom, HelmSpacing.xs)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            if showsCoachProgress {
                proxy.scrollTo("chat-progress", anchor: .bottom)
            } else if controller.isStreaming,
               let streamingText = controller.streamingText,
               shouldShowStreamingBubble(streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if controller.pendingChatAction != nil {
                proxy.scrollTo("chat-confirmation", anchor: .bottom)
            } else if !controller.pendingMemoryRefinements.isEmpty {
                proxy.scrollTo("memory-refinements", anchor: .bottom)
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

#if DEBUG
#Preview("Memory refinement card") {
    VStack {
        MemoryRefinementConfirmationCard(
            refinements: [
                MemoryRefinementEntry(
                    field: "preferences",
                    action: .add,
                    proposedValue: "Prefers push exercises over pull. Likes high volume shoulder work on Tuesdays.",
                    confidence: .high,
                    evidence: [],
                    rationale: "Athlete repeatedly chose push variations."
                )
            ],
            onAcceptAll: {},
            onDismiss: {}
        )
        .helmScreenPadding()
        .padding()
    }
    .helmTheme()
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
#endif
