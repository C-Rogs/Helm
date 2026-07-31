import Foundation

/// Tracks which exercise the remove-confirmation dialog targets.
///
/// SwiftUI's `confirmationDialog` Binding often clears `pendingID` on dismiss
/// before the destructive button's `Task` runs. Prefer the dialog's
/// `presenting` value when confirming so remove still lands.
public struct PendingExerciseRemoval: Equatable, Sendable {
    public private(set) var pendingID: String?

    public init(pendingID: String? = nil) {
        self.pendingID = pendingID
    }

    public mutating func request(_ sessionExerciseID: String) {
        pendingID = sessionExerciseID
    }

    public mutating func cancel() {
        pendingID = nil
    }

    /// Returns the exercise to remove and clears pending state.
    /// - Parameter presentingID: ID captured by the confirmation dialog when it opened.
    public mutating func confirm(presentingID: String?) -> String? {
        let id = presentingID ?? pendingID
        pendingID = nil
        return id
    }
}
