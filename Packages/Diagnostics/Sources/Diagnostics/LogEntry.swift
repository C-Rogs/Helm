import Foundation

public struct LogEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let level: LogLevel
    public let message: String
    public let context: [String: String]?
    public let errorType: String?
    public let stackTrace: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        category: String,
        level: LogLevel,
        message: String,
        context: [String: String]? = nil,
        errorType: String? = nil,
        stackTrace: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.level = level
        self.message = message
        self.context = context
        self.errorType = errorType
        self.stackTrace = stackTrace
    }
}
