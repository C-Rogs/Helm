import Foundation

public protocol MealVisionProviding: Sendable {
    func decompose(imageJPEGData: Data) async throws -> MealDecomposition
}
