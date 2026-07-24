import Core
import Foundation

public protocol MealMacroEstimating: Sendable {
    func estimateMacros(imageJPEGData: Data) async throws -> MealEstimate
}
