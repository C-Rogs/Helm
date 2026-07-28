import Foundation

public protocol MealVisionProviding: Sendable {
    func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition
}
