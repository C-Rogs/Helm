import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
    case migrationFailed(String)
    case recordNotFound(String)
}

extension PersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .migrationFailed(let detail):
            return "Database migration failed: \(detail)"
        case .recordNotFound(let detail):
            return "Record not found: \(detail)"
        }
    }
}
