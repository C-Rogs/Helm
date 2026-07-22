import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
    case migrationFailed(String)
    case recordNotFound(String)
    case activeSessionAlreadyExists
    case noActiveSession
}

extension PersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .migrationFailed(let detail):
            return "Database migration failed: \(detail)"
        case .recordNotFound(let detail):
            return "Record not found: \(detail)"
        case .activeSessionAlreadyExists:
            return "An active workout session is already in progress"
        case .noActiveSession:
            return "No active workout session"
        }
    }
}
