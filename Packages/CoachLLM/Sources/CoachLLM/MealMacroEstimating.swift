import Core
import Foundation

public protocol MealMacroEstimating: Sendable {
    func estimateMacros(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate
}
