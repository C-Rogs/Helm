import CoachLLM
import Foundation

public enum CoachHistoryExport: Sendable {
    public static let maxCharacterCount = LinearFeedbackClient.maxCoachHistoryCharacters

    /// Only attach turns near the bug submit time (not weeks of workout chat).
    public static let feedbackLookback: TimeInterval = 48 * 60 * 60

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    public static func markdown(from messages: [StoredChatMessage]) -> String {
        markdown(chat: messages, train: [], now: Date())
    }

    /// Chat tab plus Train Ask Coach. Train is last so clipping keeps the newest session turns.
    /// Messages older than `feedbackLookback` before `now` are dropped so Linear bugs
    /// cross-reference the submit timestamp instead of stale transcripts.
    public static func markdown(
        chat: [StoredChatMessage],
        train: [StoredChatMessage],
        now: Date = Date(),
        lookback: TimeInterval = feedbackLookback
    ) -> String {
        let cutoff = now.addingTimeInterval(-lookback)
        var sections: [String] = []
        let chatBody = transcript(from: chat.filter { $0.createdAt >= cutoff })
        if !chatBody.isEmpty {
            sections.append("### Chat\n\n\(chatBody)")
        }
        let trainBody = transcript(from: train.filter { $0.createdAt >= cutoff })
        if !trainBody.isEmpty {
            sections.append("### Train coach\n\n\(trainBody)")
        }
        if sections.isEmpty {
            return ""
        }
        let windowNote = "_Window: last \(Int(lookback / 3600))h before submit (\(Self.timestampFormatter.string(from: cutoff)) → \(Self.timestampFormatter.string(from: now)))._"
        return LinearFeedbackClient.clipCoachHistory(
            ([windowNote] + sections).joined(separator: "\n\n")
        )
    }

    private static func transcript(from messages: [StoredChatMessage]) -> String {
        messages.map { message in
            let role: String
            switch message.role {
            case .user: role = "You"
            case .assistant: role = "Coach"
            case .system: role = "System"
            }
            let stamp = timestampFormatter.string(from: message.createdAt)
            return "**\(role)** _(\(stamp)):_ \(message.text)"
        }
        .joined(separator: "\n\n")
    }
}
