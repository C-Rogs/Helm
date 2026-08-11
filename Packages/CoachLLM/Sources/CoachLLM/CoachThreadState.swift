public struct CoachMessage: Sendable, Equatable {
    public enum Role: String, Sendable, Equatable {
        case user
        case assistant
        case system
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct CoachThreadState: Sendable, Equatable {
    public static let defaultWindowSize = 20

    public var messages: [CoachMessage]
    /// Structured summary of compressed messages beyond the window.
    public var summary: ThreadContextSummary?

    public var isFollowUp: Bool {
        messages.contains { $0.role == .assistant }
    }

    public init(messages: [CoachMessage], summary: ThreadContextSummary? = nil) {
        self.messages = messages
        self.summary = summary
    }

    /// Keeps the most recent `limit` messages for token efficiency.
    public func windowed(limit: Int = Self.defaultWindowSize) -> CoachThreadState {
        guard limit > 0, messages.count > limit else { return self }
        return CoachThreadState(messages: Array(messages.suffix(limit)), summary: summary)
    }

    /// Returns messages suitable for LLM context: summary block (if present)
    /// followed by the most recent verbatim messages.
    public func messagesForContext() -> [CoachMessage] {
        var result: [CoachMessage] = []
        if let s = summary, !s.isEmpty {
            result.append(CoachMessage(role: .system, text: s.promptBlock))
        }
        result.append(contentsOf: messages)
        return result
    }

    public static let empty = CoachThreadState(messages: [])
}
