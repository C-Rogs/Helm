import Foundation

public enum CookingFatReconciler: Sendable {
    public struct ResolvedItem: Sendable, Equatable {
        public let name: String
        public let attribution: CookingFatAttribution
        public let cofidDescription: String

        public init(name: String, attribution: CookingFatAttribution, cofidDescription: String) {
            self.name = name
            self.attribution = attribution
            self.cofidDescription = cofidDescription
        }
    }

    public struct ImplicitFat: Sendable, Equatable {
        public let name: String
        public let grams: Double

        public init(name: String, grams: Double) {
            self.name = name
            self.grams = grams
        }
    }

    public struct Result: Sendable, Equatable {
        public let keptImplicitFats: [ImplicitFat]
        public let droppedImplicitFats: [ImplicitFat]
        public let warnings: [String]

        public init(
            keptImplicitFats: [ImplicitFat],
            droppedImplicitFats: [ImplicitFat],
            warnings: [String]
        ) {
            self.keptImplicitFats = keptImplicitFats
            self.droppedImplicitFats = droppedImplicitFats
            self.warnings = warnings
        }
    }

    public static func reconcile(
        items: [ResolvedItem],
        implicitFats: [ImplicitFat]
    ) -> Result {
        guard !implicitFats.isEmpty else {
            return Result(keptImplicitFats: [], droppedImplicitFats: [], warnings: [])
        }

        let hasItems = !items.isEmpty
        let hasIncludedInRow = items.contains { $0.attribution == .includedInRow }
        let hasAdditiveCandidate = items.contains { $0.attribution == .additiveCandidate }
        let cofidAlreadyHasCookingFat = items.contains {
            CookingFatAttributionClassifier.descriptionIncludesCookingFat($0.cofidDescription)
        }

        var kept: [ImplicitFat] = []
        var dropped: [ImplicitFat] = []

        for fat in implicitFats {
            if shouldDrop(
                fat,
                hasItems: hasItems,
                hasIncludedInRow: hasIncludedInRow,
                hasAdditiveCandidate: hasAdditiveCandidate,
                cofidAlreadyHasCookingFat: cofidAlreadyHasCookingFat
            ) {
                dropped.append(fat)
            } else {
                kept.append(fat)
            }
        }

        var warnings: [String] = []
        if !dropped.isEmpty {
            let names = dropped.map(\.name).joined(separator: ", ")
            warnings.append("Cooking fat already included in matched CoFID items. Removed: \(names).")
        }

        return Result(keptImplicitFats: kept, droppedImplicitFats: dropped, warnings: warnings)
    }

    private static func shouldDrop(
        _ fat: ImplicitFat,
        hasItems: Bool,
        hasIncludedInRow: Bool,
        hasAdditiveCandidate: Bool,
        cofidAlreadyHasCookingFat: Bool
    ) -> Bool {
        guard hasItems else { return false }

        let normalized = NutritionLookup.normalize(fat.name)

        if isDressingType(normalized) {
            return !hasAdditiveCandidate
        }

        if isGenericCookingFat(normalized) {
            if hasIncludedInRow || cofidAlreadyHasCookingFat {
                return true
            }
            return !hasAdditiveCandidate
        }

        return !hasAdditiveCandidate && hasIncludedInRow
    }

    private static func isGenericCookingFat(_ normalized: String) -> Bool {
        if isDressingType(normalized) { return false }
        return normalized.contains("oil")
            || normalized.contains("butter")
            || normalized.contains("ghee")
            || normalized.contains("margarine")
            || normalized.contains("lard")
            || normalized.contains("dripping")
            || normalized == "fat"
            || normalized == "cooking fat"
    }

    private static func isDressingType(_ normalized: String) -> Bool {
        normalized.contains("dressing")
            || normalized.contains("vinaigrette")
            || normalized.contains("mayonnaise")
            || normalized.contains("mayo")
            || normalized.contains("aioli")
            || normalized.contains("hollandaise")
            || normalized.contains("pesto")
    }
}
