import Core
import Foundation

public protocol MealMacroVisionProviding: MealVisionProviding {
    func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate
}
