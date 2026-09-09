import Core
import Foundation
import PlanKit

public enum SessionAdjustmentVerificationError: Error, Sendable, Equatable {
    case noPersistedChange

    public var localizedDescription: String {
        "That change did not stick in your session. Try again using the exact exercise names shown on screen."
    }
}

public enum SessionAdjustmentVerifier {
    public static func verifyPersistedChange(
        from before: SessionPrescription,
        to after: SessionPrescription
    ) throws {
        guard PrescriptionDiff.exercisesChanged(from: before, to: after) else {
            throw SessionAdjustmentVerificationError.noPersistedChange
        }
    }
}
