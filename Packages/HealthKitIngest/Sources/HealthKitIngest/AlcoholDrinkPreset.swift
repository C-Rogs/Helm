import Foundation

/// UK drink presets for explicit alcohol logging.
public enum AlcoholDrinkPreset: String, Sendable, CaseIterable, Codable {
    case beerHalfPint
    case beerThirdPint
    case beerTwoThirdsPint
    case beerPint
    case wine
    case wineLarge
    case spirit
    case aperolSpritz
    case ginAndTonic

    public enum Category: String, Sendable, CaseIterable {
        case beer
        case wine
        case spirits
        case cocktails

        public var title: String {
            switch self {
            case .beer: "Beer"
            case .wine: "Wine"
            case .spirits: "Spirits"
            case .cocktails: "Cocktails"
            }
        }

        public var presets: [AlcoholDrinkPreset] {
            AlcoholDrinkPreset.allCases.filter { $0.category == self }
        }
    }

    public var category: Category {
        switch self {
        case .beerHalfPint, .beerThirdPint, .beerTwoThirdsPint, .beerPint:
            .beer
        case .wine, .wineLarge:
            .wine
        case .spirit:
            .spirits
        case .aperolSpritz, .ginAndTonic:
            .cocktails
        }
    }

    public var displayName: String {
        switch self {
        case .beerHalfPint:
            "Beer (½ pint)"
        case .beerThirdPint:
            "Beer (⅓ pint)"
        case .beerTwoThirdsPint:
            "Beer (⅔ pint)"
        case .beerPint:
            "Beer (pint)"
        case .wine:
            "Wine (175 ml)"
        case .wineLarge:
            "Wine (250 ml)"
        case .spirit:
            "Spirit (25 ml)"
        case .aperolSpritz:
            "Aperol spritz"
        case .ginAndTonic:
            "Gin & tonic"
        }
    }

    public var servingLabel: String {
        switch self {
        case .beerHalfPint:
            "½ pint"
        case .beerThirdPint:
            "⅓ pint"
        case .beerTwoThirdsPint:
            "⅔ pint"
        case .beerPint:
            "1 pint"
        case .wine:
            "1 glass"
        case .wineLarge:
            "1 large glass"
        case .spirit:
            "1 shot"
        case .aperolSpritz:
            "1 spritz"
        case .ginAndTonic:
            "1 G&T"
        }
    }

    public var kilocaloriesPerServing: Double {
        switch self {
        case .beerHalfPint:
            105
        case .beerThirdPint:
            70
        case .beerTwoThirdsPint:
            140
        case .beerPint:
            210
        case .wine:
            133
        case .wineLarge:
            190
        case .spirit:
            61
        case .aperolSpritz:
            140
        case .ginAndTonic:
            120
        }
    }

    public var proteinGramsPerServing: Double {
        switch self {
        case .beerHalfPint, .beerThirdPint, .beerTwoThirdsPint, .beerPint:
            2
        case .wine, .wineLarge, .spirit, .aperolSpritz, .ginAndTonic:
            0
        }
    }

    public var carbohydrateGramsPerServing: Double {
        switch self {
        case .beerHalfPint:
            8.5
        case .beerThirdPint:
            5.5
        case .beerTwoThirdsPint:
            11
        case .beerPint:
            17
        case .wine:
            3
        case .wineLarge:
            4
        case .spirit:
            0
        case .aperolSpritz:
            12
        case .ginAndTonic:
            8
        }
    }

    public var fatGramsPerServing: Double { 0 }

    /// Backward-compatible alias for persisted `.beer` raw values.
    public static var beer: AlcoholDrinkPreset { .beerPint }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if raw == "beer" {
            self = .beerPint
            return
        }
        guard let preset = AlcoholDrinkPreset(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown alcohol preset: \(raw)"
            )
        }
        self = preset
    }

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
