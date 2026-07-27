import DesignSystem
import HealthKitIngest
import SwiftUI

struct InSessionCoachSheet: View {
    @Bindable var controller: TrainSessionController
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: HelmSpacing.md) {
                            if controller.coachMessages.isEmpty, !controller.isCoachThinking {
                                emptyState
                            }

                            ForEach(controller.coachMessages) { message in
                                CoachMessageBubble(
                                    role: message.role == .user ? .user : .assistant,
                                    text: message.text
                                )
                                .id(message.id)
                            }

                            if controller.isCoachThinking {
                                CoachMessageBubble(role: .assistant, text: "", isStreaming: true)
                                    .id("coach-thinking")
                            }

                            if let proposal = controller.pendingCoachProposal {
                                confirmationRow(proposal)
                                    .id("coach-confirmation")
                            }
                        }
                        .padding(HelmSpacing.md)
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
                }

                composer
            }
            .helmScreenBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        controller.isShowingCoachPrompt = false
                    }
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
        .presentationDetents([.large])
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
                .disabled(controller.isCoachThinking)

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
            )
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface.opacity(0.96))
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(HelmMotion.standardAnimation) {
            if controller.pendingCoachProposal != nil {
                proxy.scrollTo("coach-confirmation", anchor: .bottom)
            } else if controller.isCoachThinking {
                proxy.scrollTo("coach-thinking", anchor: .bottom)
            } else if let last = controller.coachMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

#if DEBUG
#Preview("In-session coach advisory") {
    InSessionCoachSheet(controller: TrainBootstrap.sessionController)
        .helmTheme()
}
#endif
