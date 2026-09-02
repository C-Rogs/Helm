import CoachLLM
import DesignSystem
import Persistence
import SwiftUI

struct FeedbackView: View {
    @State private var kind: LinearFeedbackKind = .bug
    @State private var title = ""
    @State private var details = ""
    @State private var fromName = FriendsReleasePreferences.shared.feedbackFromName
    @State private var includeCoachHistory = false
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var didSend = false

    private let client = LinearFeedbackClient()

    var body: some View {
        Form {
            if didSend {
                Section {
                    Text("Got it. Cam will see it.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            } else {
                Section {
                    Picker("Kind", selection: $kind) {
                        Text("Bug").tag(LinearFeedbackKind.bug)
                        Text("Idea").tag(LinearFeedbackKind.feature)
                    }
                    .pickerStyle(.segmented)
                    .helmListRowChrome()
                } footer: {
                    Text("Bug if it's broken. Idea if you want something new.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }

                Section {
                    TextField("Your name", text: $fromName)
                        .textInputAutocapitalization(.words)
                    TextField(kind == .bug ? "What's broken?" : "What do you want?", text: $title)
                    TextField("A bit more. What did you tap? What should happen?", text: $details, axis: .vertical)
                        .lineLimit(4 ... 8)
                }

                Section {
                    Toggle("Include coach history", isOn: $includeCoachHistory)
                    Text("Attaches Chat and Train coach threads so Cam can see both.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .helmType(.body, color: HelmColor.depleted)
                    }
                }

                Section {
                    Button(isSending ? "Sending…" : "Send") {
                        Task { await send() }
                    }
                    .disabled(isSending)
                }
            }
        }
        .navigationTitle("Feedback")
        .helmScreenBackground()
        .scrollContentBackground(.hidden)
    }

    @MainActor
    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let trimmedName = fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        FriendsReleasePreferences.shared.feedbackFromName = trimmedName

        var history: String?
        if includeCoachHistory {
            let store = PersistenceBootstrap.persistenceStore
            let chat = (try? store.chat.fetchRecent(limit: ChatStore.feedbackChatLimit, surface: .chat)) ?? []
            let train = (try? store.chat.fetchRecent(limit: ChatStore.trainRetentionLimit, surface: .train)) ?? []
            let markdown = CoachHistoryExport.markdown(chat: chat, train: train)
            if !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                history = markdown
            }
        }

        do {
            _ = try await client.submit(
                LinearFeedbackDraft(
                    kind: kind,
                    title: title,
                    details: details,
                    fromName: trimmedName,
                    coachHistoryMarkdown: history
                )
            )
            HapticEngine.shared.play(.selection)
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
    }
    .helmTheme()
}
