import CoachLLM
import Core
import Diagnostics
import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

private let photoMealLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public enum PhotoMealError: Error, Sendable, Equatable {
    case imageTooLarge
    case invalidImage
}

public struct PhotoMealService: Sendable {
    private let estimator: any MealMacroEstimating
    private let persister: PhotoMealPersister

    public init(
        estimator: any MealMacroEstimating,
        writer: any MealHealthKitWriting = MealHealthKitWriter(),
        localStore: PhotoMealLocalStore? = nil,
        hkWrites: MealHealthKitWriteQueue = MealHealthKitWriteQueue()
    ) {
        self.estimator = estimator
        persister = PhotoMealPersister(writer: writer, localStore: localStore, hkWrites: hkWrites)
    }

    public func flushHealthKitWrites() async {
        await persister.flushHealthKitWrites()
    }

    public func estimate(
        from imageJPEGData: Data,
        userNotes: String? = nil,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        guard !imageJPEGData.isEmpty else {
            throw PhotoMealError.invalidImage
        }
        let payload = try Self.normalizedPayload(from: imageJPEGData)

        do {
            let estimate = try await estimator.estimateMacros(
                imageJPEGData: payload,
                userNotes: userNotes,
                portionAssist: portionAssist,
                progress: progress
            )
            photoMealLog.debug(
                "Photo estimate kcal=\(estimate.caloriesKcal, privacy: .public) confidence=\(estimate.confidence.rawValue, privacy: .public) items=\(estimate.lineItems.count, privacy: .public)"
            )
            Task {
                var context: [String: String] = [
                    "kcal": String(Int(estimate.caloriesKcal.rounded())),
                    "protein_g": String(format: "%.1f", estimate.proteinG),
                    "confidence": estimate.confidence.rawValue,
                    "line_items": String(estimate.lineItems.count)
                ]
                if !estimate.groundingWarnings.isEmpty {
                    context["warnings"] = estimate.groundingWarnings.joined(separator: " | ")
                }
                if let direct = estimate.visionDirectEstimate {
                    context["vision_kcal"] = String(Int(direct.caloriesKcal.rounded()))
                }
                if let audit = estimate.decompositionAuditJSON {
                    let capped = audit.count > 4000 ? String(audit.prefix(4000)) + "…" : audit
                    context["decomposition_json"] = capped
                }
                if let portionAssist {
                    context["lidar_scale"] = String(format: "%.2f", portionAssist.gramScaleFactor)
                    context["lidar_depth_m"] = String(format: "%.2f", portionAssist.medianDepthMeters)
                }
                await DiagnosticsLog.shared.record(
                    category: .nutritionKit,
                    level: .debug,
                    message: "Photo meal grounded estimate",
                    context: context
                )
            }
            return estimate
        } catch {
            photoMealLog.error("Photo macro estimate failed: \(String(describing: type(of: error)), privacy: .public)")
            Task { await DiagnosticsLog.shared.capture(error: error, category: .nutritionKit, message: "Photo macro estimate failed") }
            throw error
        }
    }

    public func confirm(
        estimate: MealEstimate,
        name: String,
        bucket: MealBucket = .snacks,
        loggedAt: Date = Date(),
        helmDay: HelmDay? = nil,
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        try await persister.confirm(
            estimate: estimate,
            name: name,
            bucket: bucket,
            loggedAt: loggedAt,
            helmDay: helmDay,
            mealID: mealID
        )
    }

    public static func userMessage(for error: Error) -> String {
        if let photoError = error as? PhotoMealError {
            switch photoError {
            case .imageTooLarge:
                return "That photo is too large. Try a smaller image."
            case .invalidImage:
                return "Could not read that image."
            }
        }

        if let providerError = error as? CoachProviderError {
            return nutritionMessage(for: providerError)
        }

        return CoachFailurePolicy.degradedState(for: error).userMessage
    }

    private static func nutritionMessage(for error: CoachProviderError) -> String {
        switch error {
        case .rateLimited:
            return "Photo analysis is rate limited. Try again shortly."
        case .timeout:
            return "Photo analysis timed out. Check your connection and try again."
        case .offline:
            return "Photo analysis needs a network connection."
        case .unavailable(let message):
            return message
        case .contextTooLarge:
            return "That photo could not be analysed. Try a smaller image."
        case .cancelled:
            return "Photo analysis cancelled."
        case .requestFailed(let detail):
            return "Could not analyse that photo (\(detail))."
        }
    }

    static let maxJPEGBytes = 4 * 1_024 * 1_024

    private static func normalizedPayload(from imageJPEGData: Data) throws -> Data {
        if imageJPEGData.count <= maxJPEGBytes {
            return imageJPEGData
        }
        #if canImport(UIKit)
        if let image = UIImage(data: imageJPEGData),
           let prepared = MealPhotoJPEGPreparer.prepare(from: image) {
            return prepared
        }
        #endif
        throw PhotoMealError.imageTooLarge
    }
}
