import Foundation

public actor DiagnosticsLog {
    public static let shared = DiagnosticsLog()
    public static let capacity = 500

    private var buffer: [LogEntry] = []

    public init() {}

    public func record(
        category: HelmCategory,
        level: LogLevel,
        message: String,
        context: [String: String]? = nil
    ) {
        append(
            LogEntry(
                timestamp: Date(),
                category: category.rawValue,
                level: level,
                message: message,
                context: context
            )
        )
    }

    public func capture(
        error: Error,
        category: HelmCategory,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        let errorType = String(reflecting: type(of: error))
        let stackTrace = Thread.callStackSymbols.joined(separator: "\n")
        let resolvedMessage = message ?? String(describing: error)

        append(
            LogEntry(
                timestamp: Date(),
                category: category.rawValue,
                level: .error,
                message: resolvedMessage,
                context: context,
                errorType: errorType,
                stackTrace: stackTrace
            )
        )
    }

    public func entriesOldestFirst() -> [LogEntry] {
        buffer
    }

    public func entriesNewestFirst() -> [LogEntry] {
        buffer.reversed()
    }

    public func count() -> Int {
        buffer.count
    }

    public func clear() {
        buffer.removeAll(keepingCapacity: true)
    }

    private func append(_ entry: LogEntry) {
        if buffer.count >= Self.capacity {
            buffer.removeFirst(buffer.count - Self.capacity + 1)
        }
        buffer.append(entry)
    }
}

public enum SilentFailure {
    @discardableResult
    public static func run<T>(
        log: DiagnosticsLog = .shared,
        category: HelmCategory,
        context: [String: String] = [:],
        _ operation: () async throws -> T
    ) async -> T? {
        do {
            return try await operation()
        } catch {
            await log.capture(error: error, category: category, context: context)
            return nil
        }
    }
}
