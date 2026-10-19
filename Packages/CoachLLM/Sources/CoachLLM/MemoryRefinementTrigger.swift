import Foundation

/// Decides when chat should run a background memory-refinement extraction pass.
public enum MemoryRefinementTrigger: Sendable {
    public struct Turn: Sendable, Equatable {
        public let isUser: Bool
        public let text: String
        public let createdAt: Date

        public init(isUser: Bool, text: String, createdAt: Date) {
            self.isUser = isUser
            self.text = text
            self.createdAt = createdAt
        }
    }

    /// Minimum user+assistant turns before extraction is useful.
    public static let minimumTurns = 6
    /// Do not re-extract more often than this.
    public static let cooldown: TimeInterval = 4 * 60 * 60
    /// Keep the most recent turns for the extractor prompt.
    public static let sessionWindowLimit = 20

    public static func shouldExtract(
        messages: [Turn],
        lastExtraction: Date?,
        now: Date = Date()
    ) -> Bool {
        guard messages.count >= minimumTurns else { return false }
        if let lastExtraction, now.timeIntervalSince(lastExtraction) < cooldown {
            return false
        }
        let userTurns = messages.filter(\.isUser)
        guard userTurns.count >= 2 else { return false }
        // Skip greeting-only or tiny threads.
        let substantive = userTurns.contains { turn in
            turn.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 24
        }
        return substantive
    }

    public static func sessionWindow(from messages: [Turn]) -> [Turn] {
        Array(messages.suffix(sessionWindowLimit))
    }
}
