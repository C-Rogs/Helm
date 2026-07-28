import Core
import Foundation
import NutritionKit

public struct GroundedPhotoMacroEstimator: Sendable {
    private let vision: any MealMacroVisionProviding
    private let lookup: NutritionLookup

    public init(vision: any MealMacroVisionProviding, lookup: NutritionLookup = NutritionLookup()) {
        self.vision = vision
        self.lookup = lookup
    }

    public func estimateMacros(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
        let decomposition = try await vision.decompose(imageJPEGData: imageJPEGData, userNotes: userNotes)
        let auditJSON = encodeDecompositionAudit(decomposition)
        var estimate = aggregate(decomposition, decompositionAuditJSON: auditJSON)

        let needsDirectCheck = estimate.confidence == .low
            || estimate.lineItems.contains(where: \.usesGenericCofidFallback)
            || !estimate.groundingWarnings.isEmpty

        if needsDirectCheck {
            if let direct = try? await vision.estimateMacrosDirect(imageJPEGData: imageJPEGData, userNotes: userNotes) {
                let comparison = MealEstimate.VisionMacroComparison(
                    caloriesKcal: direct.caloriesKcal,
                    proteinG: direct.proteinG,
                    carbsG: direct.carbsG,
                    fatG: direct.fatG,
                    confidence: direct.confidence
                )
                estimate.visionDirectEstimate = comparison
                if let divergence = Self.calorieDivergencePercent(grounded: estimate, direct: comparison), divergence > 15 {
                    estimate.groundingWarnings.append(
                        "CoFID totals differ from direct vision by \(Int(divergence.rounded()))% on calories. Review ingredients."
                    )
                }
            }
        }

        return estimate
    }

    public func aggregate(
        _ decomposition: MealDecomposition,
        decompositionAuditJSON: String? = nil
    ) -> MealEstimate {
        let allItems = decomposition.items + decomposition.implicitFats
        var warnings: [String] = []
        if let portionNotes = decomposition.portionNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !portionNotes.isEmpty {
            warnings.append("Portion notes: \(portionNotes)")
        }

        let lineItems = allItems.compactMap { item -> MealLineItem? in
            guard let resolved = lookup.resolve(item: item.name) else { return nil }
            let confidence = MealEstimate.Confidence(rawValue: item.confidence.rawValue) ?? .medium
            if resolved.matchConfidence == .fallback {
                warnings.append("\(item.name) had no CoFID match. Using generic dish macros. Tap the ingredient to fix.")
            }
            return MacroAggregator.lineItem(
                name: item.name,
                grams: item.estimatedGrams,
                resolved: resolved,
                itemConfidence: confidence
            )
        }

        return MacroAggregator.sum(
            description: decomposition.mealDescription,
            lineItems: lineItems,
            groundingWarnings: warnings,
            decompositionAuditJSON: decompositionAuditJSON
        )
    }

    private func encodeDecompositionAudit(_ decomposition: MealDecomposition) -> String? {
        let payload = MealDecompositionPayload(
            schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
            mealDescription: decomposition.mealDescription,
            items: decomposition.items,
            implicitFats: decomposition.implicitFats,
            portionNotes: decomposition.portionNotes
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func calorieDivergencePercent(
        grounded: MealEstimate,
        direct: MealEstimate.VisionMacroComparison
    ) -> Double? {
        guard direct.caloriesKcal > 0 else { return nil }
        let delta = abs(grounded.caloriesKcal - direct.caloriesKcal)
        return (delta / direct.caloriesKcal) * 100
    }
}

extension GroundedPhotoMacroEstimator: MealMacroEstimating {}
