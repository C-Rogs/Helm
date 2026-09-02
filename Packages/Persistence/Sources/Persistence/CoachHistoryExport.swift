import CoachLLM
import Foundation

public enum CoachHistoryExport: Sendable {
    public static let maxCharacterCount = LinearFeedbackClient.maxCoachHistoryCharacters

    public static func markdown(from messages: [StoredChatMessage]) -> String {
        markdown(chat: messages, train: [])
    }

    /// Chat tab plus Train Ask Coach. Train is last so clipping keeps the newest session turns.
    public static func markdown(
        chat: [StoredChatMessage],
        train: [StoredChatMessage]
    ) -> String {
        var sections: [String] = []
        let chatBody = transcript(from: chat)
        if !chatBody.isEmpty {
            sections.append("### Chat\n\n\(chatBody)")
        }
        let trainBody = transcript(from: train)
        if !trainBody.isEmpty {
            sections.append("### Train coach\n\n\(trainBody)")
        }
        return LinearFeedbackClient.clipCoachHistory(sections.joined(separator: "\n\n"))
    }

    private static func transcript(from messages: [StoredChatMessage]) -> String {
        messages.map { message in
            let role: String
            switch message.role {
            case .user: role = "You"
            case .assistant: role = "Coach"
            case .system: role = "System"
            }
            return "**\(role):** \(message.text)"
        }
        .joined(separator: "\n\n")
    }
}
