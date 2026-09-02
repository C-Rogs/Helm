import Foundation

public struct ProducePortionOption: Sendable, Equatable {
    public let label: String
    public let grams: Double

    public init(label: String, grams: Double) {
        self.label = label
        self.grams = grams
    }
}

/// Builds portion chips for any food: branded OFF serving, portion memory, heuristics, then gram presets.
///
/// CoFID ships nutrients per 100g only (no household portions in the official dataset).
/// Open Food Facts provides `serving_size` / `serving_quantity` for branded products.
/// UK household portions (FSA Food Portion Sizes) are not bundled yet; heuristics fill the gap.
public enum PortionOptionCatalog {
    public static func options(
        for productName: String,
        cofidID: String? = nil,
        origin: FoodProductOrigin? = nil,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil,
        defaultGrams: Double = 100
    ) -> [ProducePortionOption] {
        var options: [ProducePortionOption] = []

        if let suggestedGrams, suggestedGrams > 0 {
            let label = trimmed(servingLabel) ?? defaultServingLabel(origin: origin)
            options.append(ProducePortionOption(label: label, grams: suggestedGrams))
            if !looksLikeWholeUnit(label) {
                options.insert(ProducePortionOption(label: "1 whole", grams: suggestedGrams), at: 0)
            }
        }

        if let id = cofidID, let byID = byCofidID[id] {
            options.append(contentsOf: byID)
        }

        let normalized = NutritionLookup.normalize(productName)
        for (key, keywordOptions) in byKeyword where normalized.contains(key) {
            options.append(contentsOf: keywordOptions)
        }
        let wholeProduce = ["avocado", "apple", "pear", "orange", "tomato", "potato"]
        if wholeProduce.contains(where: { normalized.contains($0) }),
           let medium = options.first(where: { $0.label.localizedCaseInsensitiveContains("medium") }),
           !options.contains(where: { $0.label.localizedCaseInsensitiveContains("whole") }) {
            options.insert(ProducePortionOption(label: "1 whole", grams: medium.grams), at: 0)
        }

        options.append(contentsOf: heuristicOptions(for: productName))

        let anchor = suggestedGrams ?? defaultGrams
        options.append(contentsOf: universalGramOptions(anchor: anchor))

        return deduplicated(options, limit: 8)
    }

    /// Backward-compatible entry point for produce-only callers.
    public static func options(for productName: String, cofidID: String? = nil) -> [ProducePortionOption] {
        options(for: productName, cofidID: cofidID, origin: .cofid, defaultGrams: 100)
    }

    /// Size variants for a countable keyword (no gram presets).
    public static func unitSizeOptions(forKeyword keyword: String) -> [ProducePortionOption] {
        byKeyword[keyword] ?? []
    }

    /// MFP-style serving-size menu: household units plus `1 g` and `100 g` for scale logging.
    public static func servingMenu(
        for productName: String,
        cofidID: String? = nil,
        origin: FoodProductOrigin? = nil,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil,
        defaultGrams: Double = 100,
        extra: [ProducePortionOption] = []
    ) -> [ProducePortionOption] {
        var result: [ProducePortionOption] = []
        var seen = Set<String>()

        func append(_ option: ProducePortionOption) {
            guard option.grams > 0 else { return }
            let key = option.label.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append(option)
        }

        for option in extra { append(option) }
        for option in options(
            for: productName,
            cofidID: cofidID,
            origin: origin,
            suggestedGrams: suggestedGrams,
            servingLabel: servingLabel,
            defaultGrams: defaultGrams
        ) {
            append(option)
        }
        append(ProducePortionOption(label: "1 g", grams: 1))
        append(ProducePortionOption(label: "100 g", grams: 100))
        return result
    }

    public enum FoodProductOrigin: Sendable, Equatable {
        case cofid
        case openFoodFacts
        case custom
    }

    private static func defaultServingLabel(origin: FoodProductOrigin?) -> String {
        switch origin {
        case .openFoodFacts:
            "1 serving"
        case .cofid, .custom, .none:
            "1 portion"
        }
    }

    private static func looksLikeWholeUnit(_ label: String) -> Bool {
        let lowered = label.lowercased()
        let unitNeedles = ["whole", "bar", "pot", "scoop", "slice", "egg", "can", "fillet"]
        return unitNeedles.contains(where: lowered.contains)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func heuristicOptions(for productName: String) -> [ProducePortionOption] {
        let normalized = NutritionLookup.normalize(productName)

        if normalized.contains("slice") || normalized.contains("bread") || normalized.contains("toast") {
            return [
                ProducePortionOption(label: "1 thin slice", grams: 25),
                ProducePortionOption(label: "1 slice", grams: 36),
                ProducePortionOption(label: "2 slices", grams: 72)
            ]
        }

        if normalized.contains("tablespoon") || normalized.contains("tbsp") {
            return [ProducePortionOption(label: "1 tbsp", grams: 15)]
        }

        if normalized.contains("teaspoon") || normalized.contains("tsp") {
            return [ProducePortionOption(label: "1 tsp", grams: 5)]
        }

        if normalized.contains("ml") || normalized.contains("drink") || normalized.contains("milk")
            || normalized.contains("juice") || normalized.contains("water") || normalized.contains("coffee")
            || normalized.contains("tea") || normalized.contains("soup") {
            return [
                ProducePortionOption(label: "1 small glass (150 ml)", grams: 150),
                ProducePortionOption(label: "1 glass (200 ml)", grams: 200),
                ProducePortionOption(label: "1 large glass (250 ml)", grams: 250)
            ]
        }

        if normalized.contains("fillet") || normalized.contains("breast") || normalized.contains("steak")
            || normalized.contains("chicken") || normalized.contains("salmon") || normalized.contains("fish") {
            return [
                ProducePortionOption(label: "1 small portion", grams: 100),
                ProducePortionOption(label: "1 portion", grams: 140),
                ProducePortionOption(label: "1 large portion", grams: 180)
            ]
        }

        if normalized.contains("yogurt") || normalized.contains("yoghurt") || normalized.contains("pot") {
            return [
                ProducePortionOption(label: "1 small pot", grams: 125),
                ProducePortionOption(label: "1 pot", grams: 170)
            ]
        }

        if normalized.contains("canned") || normalized.contains("tin") {
            return [
                ProducePortionOption(label: "1/2 can", grams: 100),
                ProducePortionOption(label: "1 can", grams: 200)
            ]
        }

        if normalized.contains("rice") || normalized.contains("pasta") || normalized.contains("noodle")
            || normalized.contains("couscous") || normalized.contains("quinoa") || normalized.contains("oats") {
            return [
                ProducePortionOption(label: "1/2 cup cooked", grams: 80),
                ProducePortionOption(label: "1 cup cooked", grams: 160)
            ]
        }

        if normalized.contains("cheese") {
            return [
                ProducePortionOption(label: "1 matchbox size", grams: 30),
                ProducePortionOption(label: "1 portion", grams: 40)
            ]
        }

        if normalized.contains("butter") || normalized.contains("spread") || normalized.contains("margarine") {
            return [
                ProducePortionOption(label: "1 tsp", grams: 5),
                ProducePortionOption(label: "1 tbsp", grams: 15)
            ]
        }

        if normalized.contains("nuts") || normalized.contains("almond") || normalized.contains("peanut")
            || normalized.contains("walnut") {
            return [
                ProducePortionOption(label: "1 small handful", grams: 20),
                ProducePortionOption(label: "1 handful", grams: 30)
            ]
        }

        return []
    }

    private static func universalGramOptions(anchor: Double) -> [ProducePortionOption] {
        let roundedAnchor = max(anchor, 25)
        let candidates: [Double] = [
            max(25, (roundedAnchor * 0.5).rounded(to: 5)),
            max(50, roundedAnchor.rounded(to: 5)),
            max(75, (roundedAnchor * 1.5).rounded(to: 5)),
            max(100, (roundedAnchor * 2).rounded(to: 5))
        ]
        return deduplicatedGrams(candidates).map { grams in
            ProducePortionOption(label: "\(Int(grams)) g", grams: grams)
        }
    }

    private static func deduplicatedGrams(_ values: [Double]) -> [Double] {
        var seen = Set<Int>()
        return values.compactMap { value in
            let key = Int(value.rounded())
            guard key > 0, seen.insert(key).inserted else { return nil }
            return Double(key)
        }
    }

    private static func deduplicated(_ options: [ProducePortionOption], limit: Int) -> [ProducePortionOption] {
        var seen = Set<String>()
        var result: [ProducePortionOption] = []
        for option in options where option.grams > 0 {
            let key = option.label.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(option)
            if result.count >= limit { break }
        }
        return result
    }

    private static let byCofidID: [String: [ProducePortionOption]] = [:]

    private static let byKeyword: [String: [ProducePortionOption]] = [
        "apple": [
            ProducePortionOption(label: "1 small", grams: 130),
            ProducePortionOption(label: "1 medium", grams: 182),
            ProducePortionOption(label: "1 large", grams: 223)
        ],
        "avocado": [
            ProducePortionOption(label: "1 small", grams: 130),
            ProducePortionOption(label: "1 medium", grams: 170),
            ProducePortionOption(label: "1 large", grams: 200)
        ],
        "banana": [
            ProducePortionOption(label: "1 small", grams: 80),
            ProducePortionOption(label: "1 medium", grams: 118),
            ProducePortionOption(label: "1 large", grams: 136)
        ],
        "pineapple": [
            ProducePortionOption(label: "1 slice", grams: 84),
            ProducePortionOption(label: "1 cup chunks", grams: 165)
        ],
        "sweetcorn": [
            ProducePortionOption(label: "1 ear", grams: 90),
            ProducePortionOption(label: "1/2 cup kernels", grams: 75)
        ],
        "orange": [
            ProducePortionOption(label: "1 small", grams: 96),
            ProducePortionOption(label: "1 medium", grams: 131),
            ProducePortionOption(label: "1 large", grams: 184)
        ],
        "pear": [
            ProducePortionOption(label: "1 small", grams: 148),
            ProducePortionOption(label: "1 medium", grams: 178),
            ProducePortionOption(label: "1 large", grams: 230)
        ],
        "potato": [
            ProducePortionOption(label: "1 small", grams: 138),
            ProducePortionOption(label: "1 medium", grams: 173),
            ProducePortionOption(label: "1 large", grams: 299)
        ],
        "tomato": [
            ProducePortionOption(label: "1 cherry", grams: 17),
            ProducePortionOption(label: "1 medium", grams: 123),
            ProducePortionOption(label: "1 large", grams: 182)
        ],
        "egg": [
            ProducePortionOption(label: "1 small", grams: 38),
            ProducePortionOption(label: "1 medium", grams: 44),
            ProducePortionOption(label: "1 large", grams: 50)
        ]
    ]
}

private extension Double {
    func rounded(to step: Double) -> Double {
        (self / step).rounded() * step
    }
}
