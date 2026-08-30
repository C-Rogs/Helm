import CoachLLM
import Foundation

public enum CoachHistoryExport: Sendable {
    public static let maxCharacterCount = LinearFeedbackClient.maxCoachHistoryCharacters

    public static func markdown(from messages: [StoredChatMessage]) -> String {
        let body = messages.map { message in
            let role: String
            switch message.role {
            case .user: role = "You"
            case .assistant: role = "Coach"
            case .system: role = "System"
            }
            return "**\(role):** \(message.text)"
        }.joined(separator: "\n\n")
        return LinearFeedbackClient.clipCoachHistory(body)
    }
}
