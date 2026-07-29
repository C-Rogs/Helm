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

    public func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        let visionNotes = MealPortionAssist.augmentedUserNotes(base: userNotes, assist: portionAssist)
        if portionAssist != nil {
            progress?("Applying LiDAR depth to portion scale…")
        }
        progress?("Identifying ingredients from photo…")
        let decomposition = try await vision.decompose(imageJPEGData: imageJPEGData, userNotes: visionNotes)
        let scaledDecomposition = portionAssist.map {
            MealPortionAssist.scaledDecomposition(decomposition, scaleFactor: $0.gramScaleFactor)
        } ?? decomposition
        let auditJSON = encodeDecompositionAudit(scaledDecomposition)
        progress?("Matching ingredients to CoFID…")
        var estimate = aggregate(scaledDecomposition, decompositionAuditJSON: auditJSON)
        if let portionAssist {
            estimate.groundingWarnings.insert(MealPortionAssist.lidarWarning(for: portionAssist), at: 0)
        }

        let needsDirectCheck = estimate.confidence == .low
            || estimate.lineItems.contains(where: \.usesGenericCofidFallback)
            || estimate.lineItems.contains(where: { $0.matchConfidence == .low })
            || !estimate.groundingWarnings.isEmpty

        if needsDirectCheck {
            progress?("Cross-checking with direct vision estimate…")
            if let direct = try? await vision.estimateMacrosDirect(imageJPEGData: imageJPEGData, userNotes: visionNotes) {
                let comparison = MealEstimate.VisionMacroComparison(
                    caloriesKcal: direct.caloriesKcal,
                    proteinG: direct.proteinG,
                    carbsG: direct.carbsG,
                    fatG: direct.fatG,
                    confidence: direct.confidence
                )
                estimate.visionDirectEstimate = comparison
                if let divergence = Self.calorieDivergencePercent(grounded: estimate, direct: comparison),
                   divergence > 15 {
                    estimate.groundingWarnings.append(
                        "CoFID totals differ from direct vision by \(Int(divergence.rounded()))% on calories. Review ingredients."
                    )
                }
            }
        }

        progress?("Finalising estimate…")
        return estimate
    }

    public func aggregate(
        _ decomposition: MealDecomposition,
        decompositionAuditJSON: String? = nil
    ) -> MealEstimate {
        var warnings: [String] = []
        if let portionNotes = decomposition.portionNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !portionNotes.isEmpty {
            warnings.append("Portion notes: \(portionNotes)")
        }

        struct ResolvedDecompositionItem {
            let item: MealDecompositionPayload.Item
            let resolved: ResolvedNutrition
        }

        let resolvedItems: [ResolvedDecompositionItem] = decomposition.items.compactMap { item in
            guard let resolved = lookup.resolve(item: item.name) else { return nil }
            if resolved.matchConfidence == .fallback {
                warnings.append("\(item.name) had no CoFID match. Using generic dish macros. Tap the ingredient to fix.")
            } else if resolved.matchConfidence == .partial {
                warnings.append("\(item.name) matched \(resolved.record.description). Tap to pick a better CoFID row if needed.")
            }
            return ResolvedDecompositionItem(item: item, resolved: resolved)
        }

        let attributionInputs = resolvedItems.map { entry in
            CookingFatReconciler.ResolvedItem(
                name: entry.item.name,
                attribution: CookingFatAttributionClassifier.classify(
                    itemName: entry.item.name,
                    cofidDescription: entry.resolved.record.description,
                    fatGPer100g: entry.resolved.record.per100g.fatG
                ),
                cofidDescription: entry.resolved.record.description
            )
        }

        let reconciliation = CookingFatReconciler.reconcile(
            items: attributionInputs,
            implicitFats: decomposition.implicitFats.map {
                CookingFatReconciler.ImplicitFat(name: $0.name, grams: $0.estimatedGrams)
            }
        )
        warnings.append(contentsOf: reconciliation.warnings)

        let keptImplicitNames = Set(reconciliation.keptImplicitFats.map {
            NutritionLookup.normalize($0.name)
        })

        let lineItems = resolvedItems.compactMap { entry -> MealLineItem? in
            let confidence = MealEstimate.Confidence(rawValue: entry.item.confidence.rawValue) ?? .medium
            return MacroAggregator.lineItem(
                name: entry.item.name,
                grams: entry.item.estimatedGrams,
                resolved: entry.resolved,
                itemConfidence: confidence
            )
        } + decomposition.implicitFats.compactMap { item -> MealLineItem? in
            guard keptImplicitNames.contains(NutritionLookup.normalize(item.name)) else { return nil }
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
