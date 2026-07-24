import CoachLLM
import Core
import Diagnostics
import Foundation
import OSLog

private let photoMealLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public enum PhotoMealError: Error, Sendable, Equatable {
    case imageTooLarge
    case invalidImage
}

public struct PhotoMealService: Sendable {
    private let estimator: any MealMacroEstimating
    private let writer: any MealHealthKitWriting
    private let localStore: PhotoMealLocalStore?

    public init(
        estimator: any MealMacroEstimating,
        writer: any MealHealthKitWriting = MealHealthKitWriter(),
        localStore: PhotoMealLocalStore? = nil
    ) {
        self.estimator = estimator
        self.writer = writer
        self.localStore = localStore
    }

    public func estimate(from imageJPEGData: Data) async throws -> MealEstimate {
        guard !imageJPEGData.isEmpty else {
            throw PhotoMealError.invalidImage
        }
        guard imageJPEGData.count <= Self.maxJPEGBytes else {
            throw PhotoMealError.imageTooLarge
        }

        do {
            return try await estimator.estimateMacros(imageJPEGData: imageJPEGData)
        } catch {
            photoMealLog.error("Photo macro estimate failed: \(String(describing: type(of: error)), privacy: .public)")
            Task { await DiagnosticsLog.shared.capture(error: error, category: .nutritionKit, message: "Photo macro estimate failed") }
            throw error
        }
    }

    public func confirm(
        estimate: MealEstimate,
        name: String,
        loggedAt: Date = Date(),
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? estimate.description : trimmedName
        let request = MealWriteRequest(
            estimate: estimate,
            name: resolvedName,
            loggedAt: loggedAt,
            mealID: mealID
        )

        do {
            let saved = try await writer.saveMeal(request)
            try localStore?.recordSavedMeal(request, saved: saved)
            photoMealLog.debug("Photo meal saved mealID=\(saved.mealID, privacy: .public)")
            return saved
        } catch {
            photoMealLog.error("Photo meal write failed: \(String(describing: type(of: error)), privacy: .public)")
            Task { await DiagnosticsLog.shared.capture(error: error, category: .nutritionKit, message: "Photo meal HealthKit write failed") }
            throw error
        }
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

        return CoachFailurePolicy.degradedState(for: error).userMessage
    }

    private static let maxJPEGBytes = 4 * 1_024 * 1_024
}
