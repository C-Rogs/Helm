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

    public var isFollowUp: Bool {
        messages.contains { $0.role == .assistant }
    }

    public init(messages: [CoachMessage]) {
        self.messages = messages
    }

    /// Keeps the most recent `limit` messages for token efficiency.
    public func windowed(limit: Int = Self.defaultWindowSize) -> CoachThreadState {
        guard limit > 0, messages.count > limit else { return self }
        return CoachThreadState(messages: Array(messages.suffix(limit)))
    }

    public static let empty = CoachThreadState(messages: [])
}
