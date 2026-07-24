import Foundation

public struct NutritionFoodRecord: Sendable, Equatable, Codable {
    public struct Per100g: Sendable, Equatable, Codable {
        public let kcal: Double
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
    }

    public let fdcId: String
    public let description: String
    public let synonyms: [String]
    public let per100g: Per100g
}

struct NutritionFoodBundle: Decodable {
    let foods: [NutritionFoodRecord]
}
