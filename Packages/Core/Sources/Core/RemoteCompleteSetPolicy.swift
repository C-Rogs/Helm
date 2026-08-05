import Foundation

/// Policy for Watch / Live Activity remote set completion (never toggle uncomplete).
public enum RemoteCompleteSetPolicy: Sendable {
    /// Apply only when the set is not already completed.
    public static func shouldApply(status: SetStatus) -> Bool {
        status != .completed
    }
}
