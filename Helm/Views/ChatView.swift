import CoachLLM
import DesignSystem
import Persistence
import SwiftUI

struct ChatView: View {
    @Bindable private var controller = ChatBootstrap.controller
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let degradedState = controller.degradedState {
                    offlineBanner(degradedState)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: HelmSpacing.md) {
                            if controller.messages.isEmpty, !controller.isStreaming, controller.lastTurnError == nil {
                                emptyState
                            }

                            ForEach(controller.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if let lastTurnError = controller.lastTurnError {
                                errorBubble(lastTurnError)
                                    .id("last-turn-error")
                            }

                            if controller.isStreaming, let streamingText = controller.streamingText {
                                assistantBubble(streamingText, isStreaming: true)
                                    .id("streaming")
                            }
                        }
                        .padding(HelmSpacing.md)
                    }
                    .onChange(of: controller.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: controller.streamingText) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                composer
            }
            .helmScreenBackground()
            .navigationTitle("Chat")
            .onAppear {
                Task { await controller.onAppear() }
            }
            .onDisappear {
                controller.onDisappear()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Ask why")
                .helmType(.title)
            Text("Coach answers from your readiness, training, and nutrition data. Offline keeps numbers and logging working.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, HelmSpacing.xl)
    }

    private func offlineBanner(_ state: CoachDegradedState) -> some View {
        HStack(spacing: HelmSpacing.sm) {
            Image(systemName: "wifi.slash")
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
                userBubble(message.text)
            case .assistant:
                assistantBubble(message.text, isStreaming: false)
            case .system:
                EmptyView()
            }
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: HelmSpacing.xl)
            Text(text)
                .helmType(.body)
                .foregroundStyle(HelmColor.fg)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }

    private func assistantBubble(_ text: String, isStreaming: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("COACH")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(text.isEmpty && isStreaming ? "…" : text)
                    .helmType(.body)
                    .foregroundStyle(HelmColor.fg)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            Spacer(minLength: HelmSpacing.xl)
        }
    }

    private func errorBubble(_ message: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("COACH")
                    .helmType(.monoTag, color: HelmColor.depleted)
                Text("Couldn't respond. \(message)")
                    .helmType(.body, color: HelmColor.depleted)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            Spacer(minLength: HelmSpacing.xl)
        }
    }

    private var composer: some View {
        HStack(spacing: HelmSpacing.sm) {
            TextField("Ask the coach", text: $controller.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 4)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                .focused($isInputFocused)
                .disabled(!controller.isCoachAvailable || controller.isStreaming)

            Button {
                HapticEngine.shared.play(.selection)
                controller.send()
                isInputFocused = false
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        canSend ? HelmColor.accent : HelmColor.fgMuted
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface)
    }

    private var canSend: Bool {
        controller.isCoachAvailable
            && !controller.isStreaming
            && !controller.draftText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if controller.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastID = controller.messages.last?.id {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

#Preview {
    ChatView()
        .helmTheme()
}
