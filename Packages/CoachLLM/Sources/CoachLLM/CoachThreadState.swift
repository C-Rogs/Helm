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
    public var messages: [CoachMessage]

    public var isFollowUp: Bool {
        messages.contains { $0.role == .assistant }
    }

    public init(messages: [CoachMessage]) {
        self.messages = messages
    }

    public static let empty = CoachThreadState(messages: [])
}
