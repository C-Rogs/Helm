import Foundation

/// UK drink presets for explicit alcohol logging.
public enum AlcoholDrinkPreset: String, Sendable, CaseIterable, Codable {
    case beer
    case wine
    case spirit

    public var displayName: String {
        switch self {
        case .beer:
            "Beer (pint)"
        case .wine:
            "Wine (175 ml)"
        case .spirit:
            "Spirit (25 ml)"
        }
    }

    public var servingLabel: String {
        switch self {
        case .beer:
            "1 pint"
        case .wine:
            "1 glass"
        case .spirit:
            "1 shot"
        }
    }

    public var kilocaloriesPerServing: Double {
        switch self {
        case .beer:
            210
        case .wine:
            133
        case .spirit:
            61
        }
    }

    public var proteinGramsPerServing: Double {
        switch self {
        case .beer:
            2
        case .wine, .spirit:
            0
        }
    }

    public var carbohydrateGramsPerServing: Double {
        switch self {
        case .beer:
            17
        case .wine:
            3
        case .spirit:
            0
        }
    }

    public var fatGramsPerServing: Double { 0 }

    public func macros(quantity: Int) -> FoodPortionMacros {
        let count = Double(max(quantity, 1))
        return FoodPortionMacros(
            energyKcal: kilocaloriesPerServing * count,
            proteinG: proteinGramsPerServing * count,
            carbsG: carbohydrateGramsPerServing * count,
            fatG: fatGramsPerServing * count
        )
    }
}

public struct FoodPortionMacros: Sendable, Equatable {
    public let energyKcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double

    public init(energyKcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}

extension ResolvedFoodProduct {
    public func macros(forGrams grams: Double) -> FoodPortionMacros {
        let scale = grams / 100.0
        return FoodPortionMacros(
            energyKcal: per100gKcal * scale,
            proteinG: per100gProteinG * scale,
            carbsG: per100gCarbsG * scale,
            fatG: per100gFatG * scale
        )
    }
}
