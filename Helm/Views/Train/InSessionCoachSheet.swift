import DesignSystem
import HealthKitIngest
import SwiftUI
import UIKit

struct InSessionCoachSheet: View {
    @Bindable var controller: TrainSessionController
    @Bindable private var activityGate = CoachActivityGate.shared
    @FocusState private var isInputFocused: Bool
    @State private var didCopyExport = false

    private var coachName: String { CoachDisplayNameStore.name }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = activityGate.blockingMessage(for: .inSession) {
                    Text(message)
                        .helmType(.body, color: HelmColor.depleted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(HelmSpacing.md)
                        .background(HelmColor.surface)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: HelmSpacing.md) {
                            if controller.coachMessages.isEmpty, !controller.isCoachThinking, controller.coachTurnError == nil {
                                emptyState
                            }

                            ForEach(controller.coachMessages) { message in
                                CoachMessageBubble(
                                    role: message.role == .user ? .user : .assistant,
                                    text: message.text,
                                    coachName: coachName
                                )
                                .id(message.id)
                            }

                            if let coachTurnError = controller.coachTurnError {
                                coachErrorBubble(coachTurnError)
                                    .id("coach-turn-error")
                            }

                            if controller.isCoachThinking {
                                CoachMessageBubble(
                                    role: .assistant,
                                    text: "",
                                    isStreaming: true,
                                    coachName: coachName
                                )
                                .id("coach-thinking")
                            }

                            if let proposal = controller.pendingCoachProposal {
                                confirmationRow(proposal)
                                    .id("coach-confirmation")
                            }
                        }
                        .padding(HelmSpacing.md)
                    }
                    .onAppear {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: controller.coachMessages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.isCoachThinking) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.pendingCoachProposal?.recommendationID) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.coachTurnError) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                composer
            }
            .helmScreenBackground()
            .navigationTitle(coachName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        controller.isShowingCoachPrompt = false
                    }
                }
                if !controller.hasActiveSession, controller.prescriptionSummary != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Export") {
                            Task {
                                if let text = await controller.exportPrescriptionText() {
                                    UIPasteboard.general.string = text
                                    didCopyExport = true
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
                            Task {
                                await controller.startTodaysPrescription()
                                controller.isShowingCoachPrompt = false
                            }
                        }
                    }
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
        .presentationDetents([.fraction(0.28), .medium, .large])
        .presentationDragIndicator(.visible)
        .alert("Copied", isPresented: $didCopyExport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Prescription copied for Gemini verification.")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Ask about this session")
                .helmType(.label, color: HelmColor.fg)
            Text("Equipment swaps, set changes, load calls, or quick coaching questions.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
        .padding(.top, HelmSpacing.sm)
    }

    private func coachErrorBubble(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            CoachMessageBubble(
                role: .assistant,
                text: "Could not respond. \(message)",
                coachName: coachName
            )
            if controller.lastFailedCoachMessage != nil {
                Button("Try again") {
                    Task { await controller.retryLastCoachMessage() }
                }
                .buttonStyle(.helmSecondary)
            }
        }
    }

    private func confirmationRow(_ proposal: CoachSessionProposal) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            if let banner = proposal.previewBanner {
                AdjustmentBanner(
                    fromLabel: banner.fromLabel,
                    toLabel: banner.toLabel,
                    reason: banner.reason
                ) {}
                .allowsHitTesting(false)
            }

            HStack(spacing: HelmSpacing.sm) {
                Button("Apply change") {
                    Task { await controller.confirmCoachProposal() }
                }
                .buttonStyle(.helmPrimary)

                Button("Keep plan") {
                    Task { await controller.dismissCoachProposal() }
                }
                .buttonStyle(.helmSecondary)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: HelmSpacing.sm) {
            TextField("Ask the coach", text: $controller.coachPromptText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                .focused($isInputFocused)
                .disabled(controller.isCoachThinking || activityGate.isBlocked(for: .inSession))

            Button {
                HapticEngine.shared.play(.selection)
                Task { await controller.sendCoachMessage() }
            } label: {
                HelmIconView(.send, context: .action)
            }
            .buttonStyle(.helmPressable)
            .disabled(
                controller.coachPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || controller.isCoachThinking
                    || activityGate.isBlocked(for: .inSession)
            )
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface.opacity(0.96))
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let scroll = {
            if controller.pendingCoachProposal != nil {
                proxy.scrollTo("coach-confirmation", anchor: .bottom)
            } else if controller.coachTurnError != nil {
                proxy.scrollTo("coach-turn-error", anchor: .bottom)
            } else if controller.isCoachThinking {
                proxy.scrollTo("coach-thinking", anchor: .bottom)
            } else if let last = controller.coachMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(HelmMotion.standardAnimation) { scroll() }
        } else {
            scroll()
        }
    }
}

#if DEBUG
#Preview("In-session coach advisory") {
    InSessionCoachSheet(controller: TrainBootstrap.sessionController)
        .helmTheme()
}
#endif
