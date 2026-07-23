import Core
import Foundation

public struct PhotoMacroEstimator: Sendable {
    private let provider: GeminiProvider

    public init(provider: GeminiProvider) {
        self.provider = provider
    }

    public func estimateMacros(imageJPEGData: Data) async throws -> MealEstimate {
        let artefact = try await provider.estimateMacros(imageJPEGData: imageJPEGData)
        return MealEstimate(payload: artefact.payload)
    }
}
